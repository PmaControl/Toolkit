#!/bin/bash

set -euo pipefail

source mysql.config


#CREATE TABLE `smartd_nvme` (
#  `id` bigint(20) NOT NULL AUTO_INCREMENT,
#  `ip` varchar(15) NOT NULL,
#  `nvme` char(10) NOT NULL,
#  `date` datetime DEFAULT NULL,
#  `critical_warning` int(11) DEFAULT NULL,
#  `temperature` int(11) DEFAULT NULL COMMENT 'in °C',
#  `available_spare` int(11) DEFAULT NULL COMMENT 'in %',
#  `available_spare_threshold` int(11) DEFAULT NULL COMMENT 'in %',
#  `percentage_used` int(11) DEFAULT NULL COMMENT 'in %',
#  `endurance_group_critical_warning_summary` int(11) DEFAULT NULL,
#  `data_units_read` bigint(20) DEFAULT NULL,
#  `data_units_written` bigint(20) DEFAULT NULL,
#  `host_read_commands` bigint(20) DEFAULT NULL,
#  `host_write_commands` bigint(20) DEFAULT NULL,
#  `controller_busy_time` int(11) DEFAULT NULL,
#  `power_cycles` int(11) DEFAULT NULL,
#  `power_on_hours` int(11) DEFAULT NULL,
#  `unsafe_shutdowns` int(11) DEFAULT NULL,
#  `media_errors` int(11) DEFAULT NULL,
#  `num_err_log_entries` int(11) DEFAULT NULL,
#  `warning_temperature_time` int(11) DEFAULT NULL,
#  `critical_Composite_temperature_time` int(11) DEFAULT NULL,
#  `thermal_Management_t1_trans_Count` int(11) DEFAULT NULL,
#  `thermal_Management_t2_trans_Count` int(11) DEFAULT NULL,
#  `thermal_Management_t1_total_time` int(11) DEFAULT NULL,
#  `thermal_Management_t2_total_time` int(11) DEFAULT NULL,
#  PRIMARY KEY (`id`)
#) ENGINE=InnoDB AUTO_INCREMENT=377 DEFAULT CHARSET=latin1 COLLATE=latin1_swedish_ci COMMENT='Integration of result nvme smart-log /dev/nvme0~x, by script export_temperature.sh'



# SELECT `ip`, `nvme`, min(`temperature`), avg(`temperature`), max(`temperature`)FROM `smartd_nvme` WHERE 1 group by `ip`, `nvme`;

function extract_property_value() {
    local property_name="$1"
    if [[ $smart_data =~ $property_name[[:space:]]+:[[:space:]]+([0-9]+)% ]]; then
        echo "${BASH_REMATCH[1]}"
    fi
}

# Function to parse SMART log and insert data into MySQL table
insert_smart_data() {
    local device=$1
    local ip=$2
    local date=$(date +"%Y-%m-%d %H:%M:%S")
    
    # Parse nvme smart-log output and extract required data
    smart_data=$(/usr/sbin/nvme smart-log "$device")
    critical_warning=$(echo "$smart_data" | awk -F: '/critical_warning/ {gsub(/,/, "", $2); print $2}')
    temperature=$(echo "$smart_data" | awk -F: '/temperature/ {gsub(/ C/, "", $2); gsub(/,/, "", $2); print $2}')

    available_spare_value=$(extract_property_value "available_spare")
    # Trim des variables "available_spare" et "available_spare_threshold"
    trimmed_available_spare_value="${available_spare_value#"${available_spare_value%%[![:space:]]*}"}"
    available_spare="${trimmed_available_spare_value%"${trimmed_available_spare_value##*[![:space:]]}"}"

    #available_spare=$(echo "$smart_data" | awk -F: '/available_spare/ {gsub(/%/, "", $2); print $2}')
    available_spare_threshold=$(echo "$smart_data" | awk -F: '/available_spare_threshold/ {gsub(/%/, "", $2); print $2}')

    percentage_used=$(echo "$smart_data" | awk -F: '/percentage_used/ {gsub(/%/, "", $2); print $2}')
    endurance_group_critical_warning_summary=$(echo "$smart_data" | awk -F: '/endurance group critical warning summary/ {print $2}')
    data_units_read=$(echo "$smart_data" | awk -F: '/data_units_read/ {gsub(/,/, "", $2); print $2}')
    data_units_written=$(echo "$smart_data" | awk -F: '/data_units_written/ {gsub(/,/, "", $2); print $2}')
    host_read_commands=$(echo "$smart_data" | awk -F: '/host_read_commands/ {gsub(/,/, "", $2); print $2}')
    host_write_commands=$(echo "$smart_data" | awk -F: '/host_write_commands/ {gsub(/,/, "", $2); print $2}')
    controller_busy_time=$(echo "$smart_data" | awk -F: '/controller_busy_time/ {gsub(/,/, "", $2); print $2}')
    power_cycles=$(echo "$smart_data" | awk -F: '/power_cycles/ {gsub(/,/, "", $2); print $2}')
    power_on_hours=$(echo "$smart_data" | awk -F: '/power_on_hours/ {gsub(/,/, "", $2); print $2}')
    unsafe_shutdowns=$(echo "$smart_data" | awk -F: '/unsafe_shutdowns/ {gsub(/,/, "", $2); print $2}')
    media_errors=$(echo "$smart_data" | awk -F: '/media_errors/ {gsub(/,/, "", $2); print $2}')
    num_err_log_entries=$(echo "$smart_data" | awk -F: '/num_err_log_entries/ {gsub(/,/, "", $2); print $2}')
    warning_temperature_time=$(echo "$smart_data" | awk -F: '/Warning Temperature Time/ {gsub(/,/, "", $2); print $2}')
    critical_Composite_temperature_time=$(echo "$smart_data" | awk -F: '/Critical Composite Temperature Time/ {gsub(/,/, "", $2); print $2}')
    thermal_Management_t1_trans_Count=$(echo "$smart_data" | awk -F: '/Thermal Management T1 Trans Count/ {gsub(/,/, "", $2); print $2}')
    thermal_Management_t2_trans_Count=$(echo "$smart_data" | awk -F: '/Thermal Management T2 Trans Count/ {gsub(/,/, "", $2); print $2}')
    thermal_Management_t1_total_time=$(echo "$smart_data" | awk -F: '/Thermal Management T1 Total Time/ {gsub(/,/, "", $2); print $2}')
    thermal_Management_t2_total_time=$(echo "$smart_data" | awk -F: '/Thermal Management T2 Total Time/ {gsub(/,/, "", $2); print $2}')
 
    # MySQL command to insert data into the table
    
    /usr/bin/mysql -h ${MYSQL_IP} -u ${MYSQL_USER} -p${MYSQL_PASSWORD} -e "INSERT INTO smartd_nvme (ip, nvme, date, critical_warning, temperature, available_spare, available_spare_threshold, percentage_used, endurance_group_critical_warning_summary, data_units_read, data_units_written, host_read_commands, host_write_commands, controller_busy_time, power_cycles, power_on_hours, unsafe_shutdowns, media_errors, num_err_log_entries, warning_temperature_time, critical_Composite_temperature_time, thermal_Management_t1_trans_Count, thermal_Management_t2_trans_Count, thermal_Management_t1_total_time, thermal_Management_t2_total_time) VALUES ('$ip','$device' ,'$date', '$critical_warning', '$temperature', '$available_spare', '$available_spare_threshold', '$percentage_used', '$endurance_group_critical_warning_summary', '$data_units_read', '$data_units_written', '$host_read_commands', '$host_write_commands', '$controller_busy_time', '$power_cycles', '$power_on_hours', '$unsafe_shutdowns', '$media_errors', '$num_err_log_entries', '$warning_temperature_time', '$critical_Composite_temperature_time', '$thermal_Management_t1_trans_Count', '$thermal_Management_t2_trans_Count', '$thermal_Management_t1_total_time', '$thermal_Management_t2_total_time');" proxmox
}

# Main script starts here
# List all nvme devices
nvme_devices=$(ls -l /dev | grep nvme | awk '{print $NF}' | grep -o '^nvme[0-9]' | sort | uniq)

# Get the IPv4 address of the server on the interface vmbr0
# ip_address=$(ip -4 addr show vmbr0 | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
ip_address=$(hostname -I | awk '{print $1}')

# Loop through each nvme device and insert data into the table
for device in $nvme_devices; do
	insert_smart_data "/dev/$device" "$ip_address"
done
