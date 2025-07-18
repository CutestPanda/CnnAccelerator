if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv -dpiheader utils.h utils.c "*.sv" "../../common/*.v" "../../generic/*.v" "../../sub_module/conv_middle_res_acmlt_buf.v" "../../sub_module/conv_middle_res_accumulate.v"

# 仿真
vsim -voptargs=+acc -c tb_conv_middle_res_acmlt_buf
do wave.do
