set sql_log_bin=0;

CREATE DATABASE dba;

USE dba;


CREATE OR REPLACE
  ALGORITHM = MERGE
  DEFINER = 'root'@'localhost'
  SQL SECURITY INVOKER 
VIEW schema_unused_indexes (
  object_schema,
  object_name,
  index_name
) AS
SELECT object_schema,
       object_name,
       index_name
  FROM performance_schema.table_io_waits_summary_by_index_usage 
 WHERE index_name IS NOT NULL
   AND count_star = 0
   AND object_schema != 'mysql'
   AND index_name != 'PRIMARY'
 ORDER BY object_schema, object_name;


CREATE OR REPLACE
  ALGORITHM = TEMPTABLE
  DEFINER = 'root'@'localhost'
  SQL SECURITY INVOKER
VIEW x$schema_flattened_keys (
  table_schema,
  table_name,
  index_name,
  non_unique,
  subpart_exists,
  index_columns
) AS
  SELECT
    TABLE_SCHEMA,
    TABLE_NAME,
    INDEX_NAME,
    MAX(NON_UNIQUE) AS non_unique,
    MAX(IF(SUB_PART IS NULL, 0, 1)) AS subpart_exists,
    GROUP_CONCAT(COLUMN_NAME ORDER BY SEQ_IN_INDEX) AS index_columns
  FROM INFORMATION_SCHEMA.STATISTICS
  WHERE
    INDEX_TYPE='BTREE'
    AND TABLE_SCHEMA NOT IN ('mysql', 'sys', 'INFORMATION_SCHEMA', 'PERFORMANCE_SCHEMA')
  GROUP BY
    TABLE_SCHEMA, TABLE_NAME, INDEX_NAME;


CREATE OR REPLACE
  ALGORITHM = TEMPTABLE
  DEFINER = 'root'@'localhost'
  SQL SECURITY INVOKER
VIEW schema_redundant_indexes (
  table_schema,
  table_name,
  redundant_index_name,
  redundant_index_columns,
  redundant_index_non_unique,
  dominant_index_name,
  dominant_index_columns,
  dominant_index_non_unique,
  subpart_exists,
  sql_drop_index
) AS
  SELECT
    redundant_keys.table_schema,
    redundant_keys.table_name,
    redundant_keys.index_name AS redundant_index_name,
    redundant_keys.index_columns AS redundant_index_columns,
    redundant_keys.non_unique AS redundant_index_non_unique,
    dominant_keys.index_name AS dominant_index_name,
    dominant_keys.index_columns AS dominant_index_columns,
    dominant_keys.non_unique AS dominant_index_non_unique,
    IF(redundant_keys.subpart_exists OR dominant_keys.subpart_exists, 1 ,0) AS subpart_exists,
    CONCAT(
      'ALTER TABLE `', redundant_keys.table_schema, '`.`', redundant_keys.table_name, '` DROP INDEX `', redundant_keys.index_name, '`'
      ) AS sql_drop_index
  FROM
    x$schema_flattened_keys AS redundant_keys
    INNER JOIN x$schema_flattened_keys AS dominant_keys
    USING (TABLE_SCHEMA, TABLE_NAME)
  WHERE
    redundant_keys.index_name != dominant_keys.index_name
    AND (
      ( 
        /* Identical columns */
        (redundant_keys.index_columns = dominant_keys.index_columns)
        AND (
          (redundant_keys.non_unique > dominant_keys.non_unique)
          OR (redundant_keys.non_unique = dominant_keys.non_unique 
          	AND IF(redundant_keys.index_name='PRIMARY', '', redundant_keys.index_name) > IF(dominant_keys.index_name='PRIMARY', '', dominant_keys.index_name)
          )
        )
      )
      OR
      ( 
        /* Non-unique prefix columns */
        LOCATE(CONCAT(redundant_keys.index_columns, ','), dominant_keys.index_columns) = 1
        AND redundant_keys.non_unique = 1
      )
      OR
      ( 
        /* Unique prefix columns */
        LOCATE(CONCAT(dominant_keys.index_columns, ','), redundant_keys.index_columns) = 1
        AND dominant_keys.non_unique = 0
      )
    );


CREATE OR REPLACE
  ALGORITHM = TEMPTABLE
  DEFINER = 'root'@'localhost'
  SQL SECURITY INVOKER
VIEW `schema_index_to_delete` AS 
SELECT 1 as type_index, a.database_name, a.table_name, a.index_name,
ROUND(stat_value * 16384 / 1024 / 1024, 2) size_in_mb,
CONCAT('ALTER TABLE `', a.database_name, '`.`',a.table_name, '` DROP INDEX `', a.index_name, '`;') as query , c.NON_UNIQUE, group_concat(COLUMN_NAME)
FROM mysql.innodb_index_stats a
INNER JOIN schema_redundant_indexes b  ON  a.database_name = b.table_schema AND a.table_name = b.table_name AND b.redundant_index_name = a.index_name
INNER JOIN INFORMATION_SCHEMA.STATISTICS c ON a.database_name = c.table_schema AND a.table_name = c.table_name AND c.index_name = a.index_name
WHERE stat_name = 'size' AND a.index_name != 'PRIMARY' AND c.NON_UNIQUE=1
GROUP BY a.database_name, a.table_name, a.index_name
UNION ALL
SELECT 2 as type_index, a.database_name, a.table_name, a.index_name,
ROUND(stat_value * 16384 / 1024 / 1024, 2) size_in_mb,
CONCAT('ALTER TABLE `', a.database_name, '`.`',a.table_name, '` DROP INDEX `', a.index_name, '`;')  as query , c.NON_UNIQUE, group_concat(COLUMN_NAME)
FROM mysql.innodb_index_stats a 
INNER JOIN schema_unused_indexes b  ON  b.object_schema = a.database_name AND b.object_name = a.table_name AND b.index_name = a.index_name
INNER JOIN INFORMATION_SCHEMA.STATISTICS c ON a.database_name = c.table_schema AND a.table_name = c.table_name AND c.index_name = a.index_name
WHERE stat_name = 'size' AND a.index_name != 'PRIMARY' AND c.NON_UNIQUE=1
GROUP BY a.database_name, a.table_name, a.index_name
ORDER BY 4 desc;

