if [file exists work] {
    vdel -all
}
vlib work

# 编译HDL
vlog -sv "*.sv" "../../common/div_u16_u3.v"

# 仿真
vsim -voptargs=+acc -c tb_div_u16_u3
do wave.do
