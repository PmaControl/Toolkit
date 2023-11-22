-- Copyright (c) 2014, 2015, Oracle and/or its affiliates. All rights reserved.
--
-- This program is free software; you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation; version 3 of the License.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program; if not, write to the Free Software
-- Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA

--
-- View: ps_disk_io
--
-- Summarizes io read and io write.
--
-- mysql> select * from ps_disk_io;

-- +-----------+----------+
-- | io_read   | io_write |
-- +-----------+----------+
-- | 100381704 | 33355193 |
-- +-----------+----------+
-- 1 row in set (0,00 sec)


CREATE OR REPLACE
  ALGORITHM = MERGE
  DEFINER = 'mariadb.sys'@'localhost'
  SQL SECURITY INVOKER 
VIEW sys_schema.ps_disk_io 
(
    io_read,
    io_write
) AS
SELECT
    CONVERT(SUM(SUM_NUMBER_OF_BYTES_READ), UNSIGNED),
    CONVERT(SUM(SUM_NUMBER_OF_BYTES_WRITE), UNSIGNED)
FROM
    `performance_schema`.`file_summary_by_event_name`
WHERE
    `performance_schema`.`file_summary_by_event_name`.`EVENT_NAME` LIKE 'wait/io/file/%' AND
    `performance_schema`.`file_summary_by_event_name`.`COUNT_STAR` > 0;