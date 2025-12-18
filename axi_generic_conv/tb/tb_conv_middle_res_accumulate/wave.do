onerror {resume}
radix define fixed#23#decimal#signed -fixed -fraction 23 -signed -base signed -precision 6
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_conv_middle_res_accumulate/dut/aclk
add wave -noupdate /tb_conv_middle_res_accumulate/dut/aresetn
add wave -noupdate /tb_conv_middle_res_accumulate/dut/aclken
add wave -noupdate -radix unsigned /tb_conv_middle_res_accumulate/dut/calfmt
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_in_exp
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_in_frac
add wave -noupdate -radix hexadecimal /tb_conv_middle_res_accumulate/dut/acmlt_in_org_mid_res
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_first_item
add wave -noupdate -radix hexadecimal /tb_conv_middle_res_accumulate/dut/acmlt_out_data
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_out_valid
add wave -noupdate -radix unsigned /tb_conv_middle_res_accumulate/dut/acmlt_in_exp_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_in_frac_fp16
add wave -noupdate -radix unsigned /tb_conv_middle_res_accumulate/dut/acmlt_in_org_mid_res_exp_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_in_org_mid_res_frac_fp16
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_is_org_mid_res_dnm
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_first_item_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_org_mid_res_sub_in_exp_fp16
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_is_org_mid_res_exp_lth_in_fp16
add wave -noupdate -radix unsigned /tb_conv_middle_res_accumulate/dut/acmlt_abs_org_mid_res_sub_in_exp_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_in_abs_exp_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_in_org_mid_res_abs_exp_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_in_frac_cp2_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_in_org_mid_res_frac_cp2_fp16
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_first_item_fp16_d1
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/ars_op1
add wave -noupdate -radix unsigned /tb_conv_middle_res_accumulate/dut/ars_op2
add wave -noupdate /tb_conv_middle_res_accumulate/dut/ars_clr
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d1
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_exp_larger_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_frac_exp_lg_fp16
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_is_org_mid_res_exp_lth_in_fp16_d1
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_first_item_fp16_d2
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d2
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_frac_exp_lg_fp16_d1
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_exp_larger_fp16_d1
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_is_org_mid_res_exp_lth_in_fp16_d2
add wave -noupdate /tb_conv_middle_res_accumulate/dut/ars_op2_d1
add wave -noupdate /tb_conv_middle_res_accumulate/dut/ars_clr_d1
add wave -noupdate /tb_conv_middle_res_accumulate/dut/ars_coarse_res
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_first_item_fp16_d3
add wave -noupdate /tb_conv_middle_res_accumulate/dut/ars_res
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/adder_0_op1_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/adder_0_op2_fp16
add wave -noupdate /tb_conv_middle_res_accumulate/dut/adder_0_ce_fp16
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d3
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/adder_0_out
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_frac_sum
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_frac_shifted_fp16
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_frac_exp_lg_fp16_d2
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_exp_larger_fp16_d2
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_first_item_fp16_d4
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d4
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_frac_nml_s1
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_exp_nml_s1
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d5
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_frac_nml_s2
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_exp_nml_s2
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d6
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_frac_nml_s3
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_exp_nml_s3
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d7
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_frac_nml_s4
add wave -noupdate -radix decimal /tb_conv_middle_res_accumulate/dut/acmlt_exp_nml_s4
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d8
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_out_data_fp16
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_out_valid_fp16
add wave -noupdate /tb_conv_middle_res_accumulate/dut/acmlt_in_valid_d9
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {338112 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 286
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
WaveRestoreZoom {277074 ps} {310659 ps}
