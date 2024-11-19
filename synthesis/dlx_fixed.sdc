###################################################################

# Created by write_sdc on Sat Jul  6 03:00:51 2024

###################################################################
set sdc_version 2.1

set_units -time ns -resistance MOhm -capacitance fF -voltage V -current mA
set_wire_load_model -name 5K_hvratio_1_4 -library NangateOpenCellLibrary
create_clock [get_ports clk]  -name CLK  -period 1  -waveform {0 0.5}
set_max_delay 1  -from [list [get_ports rst] [get_ports clk] [get_ports {data_from_DM[31]}]    \
[get_ports {data_from_DM[30]}] [get_ports {data_from_DM[29]}] [get_ports       \
{data_from_DM[28]}] [get_ports {data_from_DM[27]}] [get_ports                  \
{data_from_DM[26]}] [get_ports {data_from_DM[25]}] [get_ports                  \
{data_from_DM[24]}] [get_ports {data_from_DM[23]}] [get_ports                  \
{data_from_DM[22]}] [get_ports {data_from_DM[21]}] [get_ports                  \
{data_from_DM[20]}] [get_ports {data_from_DM[19]}] [get_ports                  \
{data_from_DM[18]}] [get_ports {data_from_DM[17]}] [get_ports                  \
{data_from_DM[16]}] [get_ports {data_from_DM[15]}] [get_ports                  \
{data_from_DM[14]}] [get_ports {data_from_DM[13]}] [get_ports                  \
{data_from_DM[12]}] [get_ports {data_from_DM[11]}] [get_ports                  \
{data_from_DM[10]}] [get_ports {data_from_DM[9]}] [get_ports                   \
{data_from_DM[8]}] [get_ports {data_from_DM[7]}] [get_ports {data_from_DM[6]}] \
[get_ports {data_from_DM[5]}] [get_ports {data_from_DM[4]}] [get_ports         \
{data_from_DM[3]}] [get_ports {data_from_DM[2]}] [get_ports {data_from_DM[1]}] \
[get_ports {data_from_DM[0]}] [get_ports {data_from_IM[31]}] [get_ports        \
{data_from_IM[30]}] [get_ports {data_from_IM[29]}] [get_ports                  \
{data_from_IM[28]}] [get_ports {data_from_IM[27]}] [get_ports                  \
{data_from_IM[26]}] [get_ports {data_from_IM[25]}] [get_ports                  \
{data_from_IM[24]}] [get_ports {data_from_IM[23]}] [get_ports                  \
{data_from_IM[22]}] [get_ports {data_from_IM[21]}] [get_ports                  \
{data_from_IM[20]}] [get_ports {data_from_IM[19]}] [get_ports                  \
{data_from_IM[18]}] [get_ports {data_from_IM[17]}] [get_ports                  \
{data_from_IM[16]}] [get_ports {data_from_IM[15]}] [get_ports                  \
{data_from_IM[14]}] [get_ports {data_from_IM[13]}] [get_ports                  \
{data_from_IM[12]}] [get_ports {data_from_IM[11]}] [get_ports                  \
{data_from_IM[10]}] [get_ports {data_from_IM[9]}] [get_ports                   \
{data_from_IM[8]}] [get_ports {data_from_IM[7]}] [get_ports {data_from_IM[6]}] \
[get_ports {data_from_IM[5]}] [get_ports {data_from_IM[4]}] [get_ports         \
{data_from_IM[3]}] [get_ports {data_from_IM[2]}] [get_ports {data_from_IM[1]}] \
[get_ports {data_from_IM[0]}]]  -to [list [get_ports {address_DM_read[31]}] [get_ports {address_DM_read[30]}] \
[get_ports {address_DM_read[29]}] [get_ports {address_DM_read[28]}] [get_ports \
{address_DM_read[27]}] [get_ports {address_DM_read[26]}] [get_ports            \
{address_DM_read[25]}] [get_ports {address_DM_read[24]}] [get_ports            \
{address_DM_read[23]}] [get_ports {address_DM_read[22]}] [get_ports            \
{address_DM_read[21]}] [get_ports {address_DM_read[20]}] [get_ports            \
{address_DM_read[19]}] [get_ports {address_DM_read[18]}] [get_ports            \
{address_DM_read[17]}] [get_ports {address_DM_read[16]}] [get_ports            \
{address_DM_read[15]}] [get_ports {address_DM_read[14]}] [get_ports            \
{address_DM_read[13]}] [get_ports {address_DM_read[12]}] [get_ports            \
{address_DM_read[11]}] [get_ports {address_DM_read[10]}] [get_ports            \
{address_DM_read[9]}] [get_ports {address_DM_read[8]}] [get_ports              \
{address_DM_read[7]}] [get_ports {address_DM_read[6]}] [get_ports              \
{address_DM_read[5]}] [get_ports {address_DM_read[4]}] [get_ports              \
{address_DM_read[3]}] [get_ports {address_DM_read[2]}] [get_ports              \
{address_DM_read[1]}] [get_ports {address_DM_read[0]}] [get_ports              \
{address_DM_write[31]}] [get_ports {address_DM_write[30]}] [get_ports          \
{address_DM_write[29]}] [get_ports {address_DM_write[28]}] [get_ports          \
{address_DM_write[27]}] [get_ports {address_DM_write[26]}] [get_ports          \
{address_DM_write[25]}] [get_ports {address_DM_write[24]}] [get_ports          \
{address_DM_write[23]}] [get_ports {address_DM_write[22]}] [get_ports          \
{address_DM_write[21]}] [get_ports {address_DM_write[20]}] [get_ports          \
{address_DM_write[19]}] [get_ports {address_DM_write[18]}] [get_ports          \
{address_DM_write[17]}] [get_ports {address_DM_write[16]}] [get_ports          \
{address_DM_write[15]}] [get_ports {address_DM_write[14]}] [get_ports          \
{address_DM_write[13]}] [get_ports {address_DM_write[12]}] [get_ports          \
{address_DM_write[11]}] [get_ports {address_DM_write[10]}] [get_ports          \
{address_DM_write[9]}] [get_ports {address_DM_write[8]}] [get_ports            \
{address_DM_write[7]}] [get_ports {address_DM_write[6]}] [get_ports            \
{address_DM_write[5]}] [get_ports {address_DM_write[4]}] [get_ports            \
{address_DM_write[3]}] [get_ports {address_DM_write[2]}] [get_ports            \
{address_DM_write[1]}] [get_ports {address_DM_write[0]}] [get_ports            \
{data_to_DM[31]}] [get_ports {data_to_DM[30]}] [get_ports {data_to_DM[29]}]    \
[get_ports {data_to_DM[28]}] [get_ports {data_to_DM[27]}] [get_ports           \
{data_to_DM[26]}] [get_ports {data_to_DM[25]}] [get_ports {data_to_DM[24]}]    \
[get_ports {data_to_DM[23]}] [get_ports {data_to_DM[22]}] [get_ports           \
{data_to_DM[21]}] [get_ports {data_to_DM[20]}] [get_ports {data_to_DM[19]}]    \
[get_ports {data_to_DM[18]}] [get_ports {data_to_DM[17]}] [get_ports           \
{data_to_DM[16]}] [get_ports {data_to_DM[15]}] [get_ports {data_to_DM[14]}]    \
[get_ports {data_to_DM[13]}] [get_ports {data_to_DM[12]}] [get_ports           \
{data_to_DM[11]}] [get_ports {data_to_DM[10]}] [get_ports {data_to_DM[9]}]     \
[get_ports {data_to_DM[8]}] [get_ports {data_to_DM[7]}] [get_ports             \
{data_to_DM[6]}] [get_ports {data_to_DM[5]}] [get_ports {data_to_DM[4]}]       \
[get_ports {data_to_DM[3]}] [get_ports {data_to_DM[2]}] [get_ports             \
{data_to_DM[1]}] [get_ports {data_to_DM[0]}] [get_ports rw_to_DM] [get_ports   \
{address_IM[31]}] [get_ports {address_IM[30]}] [get_ports {address_IM[29]}]    \
[get_ports {address_IM[28]}] [get_ports {address_IM[27]}] [get_ports           \
{address_IM[26]}] [get_ports {address_IM[25]}] [get_ports {address_IM[24]}]    \
[get_ports {address_IM[23]}] [get_ports {address_IM[22]}] [get_ports           \
{address_IM[21]}] [get_ports {address_IM[20]}] [get_ports {address_IM[19]}]    \
[get_ports {address_IM[18]}] [get_ports {address_IM[17]}] [get_ports           \
{address_IM[16]}] [get_ports {address_IM[15]}] [get_ports {address_IM[14]}]    \
[get_ports {address_IM[13]}] [get_ports {address_IM[12]}] [get_ports           \
{address_IM[11]}] [get_ports {address_IM[10]}] [get_ports {address_IM[9]}]     \
[get_ports {address_IM[8]}] [get_ports {address_IM[7]}] [get_ports             \
{address_IM[6]}] [get_ports {address_IM[5]}] [get_ports {address_IM[4]}]       \
[get_ports {address_IM[3]}] [get_ports {address_IM[2]}] [get_ports             \
{address_IM[1]}] [get_ports {address_IM[0]}]]
