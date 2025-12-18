onerror {resume}
radix define fixed#10#decimal -fixed -fraction 10 -base signed -precision 6
radix define fixed#20#decimal#signed -fixed -fraction 20 -signed -base signed -precision 6
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_conv_mac_cell/dut/aclk
add wave -noupdate /tb_conv_mac_cell/dut/aresetn
add wave -noupdate -radix binary /tb_conv_mac_cell/dut/calfmt
add wave -noupdate -radix binary /tb_conv_mac_cell/dut/fp16_s_f
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_e_f
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_m_f
add wave -noupdate -radix binary /tb_conv_mac_cell/dut/fp16_s_w
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_e_w
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_m_w
add wave -noupdate /tb_conv_mac_cell/mac_in_ftm_arr
add wave -noupdate /tb_conv_mac_cell/mac_in_wgt_arr
add wave -noupdate /tb_conv_mac_cell/dut/mac_in_valid
add wave -noupdate -radix fixed#10#decimal /tb_conv_mac_cell/dut/fp16_mts_f
add wave -noupdate -radix fixed#10#decimal /tb_conv_mac_cell/dut/fp16_mts_w
add wave -noupdate -radix binary -childformat {{{/tb_conv_mac_cell/dut/fp16_mtso_sign[0]} -radix binary} {{/tb_conv_mac_cell/dut/fp16_mtso_sign[1]} -radix binary}} -subitemconfig {{/tb_conv_mac_cell/dut/fp16_mtso_sign[0]} {-radix binary} {/tb_conv_mac_cell/dut/fp16_mtso_sign[1]} {-radix binary}} /tb_conv_mac_cell/dut/fp16_mtso_sign
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_e_h3_f_add_w
add wave -noupdate /tb_conv_mac_cell/dut/mac_in_valid_d1
add wave -noupdate -radix binary /tb_conv_mac_cell/dut/fp16_mtso_sign_d1
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_e_h3_f_add_w_d1
add wave -noupdate /tb_conv_mac_cell/dut/mac_in_valid_d2
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_e_h3_f_add_w_d2
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_func
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/fp16_set
add wave -noupdate -radix fixed#20#decimal#signed /tb_conv_mac_cell/dut/fp16_signed_mtso
add wave -noupdate /tb_conv_mac_cell/dut/mac_in_valid_d3
add wave -noupdate -radix fixed#20#decimal#signed /tb_conv_mac_cell/dut/fp16_shifted_mtso
add wave -noupdate /tb_conv_mac_cell/dut/fp16_func_d1
add wave -noupdate /tb_conv_mac_cell/dut/mac_in_valid_d4
add wave -noupdate -radix fixed#20#decimal#signed /tb_conv_mac_cell/dut/add_tree_in_arr
add wave -noupdate /tb_conv_mac_cell/dut/add_tree_in_valid
add wave -noupdate -radix fixed#20#decimal#signed /tb_conv_mac_cell/dut/add_tree_out
add wave -noupdate /tb_conv_mac_cell/dut/add_tree_out_valid
add wave -noupdate -radix unsigned /tb_conv_mac_cell/dut/mac_out_exp
add wave -noupdate -radix fixed#20#decimal#signed /tb_conv_mac_cell/dut/mac_out_frac
add wave -noupdate /tb_conv_mac_cell/dut/mac_out_valid
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {146561 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 283
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 1
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {85517 ps} {220966 ps}
