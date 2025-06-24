onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/aclk
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/aresetn
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/aclken
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_dilation_hzt_n
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_dilation_vtc_n
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_w
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_h
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/rst_cvt
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/mv_to_nxt_logic_pt
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_logic_x
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_logic_y
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_phy_x
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_phy_y
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/kernal_pt_valid
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_logic_x_r
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_logic_y_r
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_phy_x_r
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/kernal_phy_y_r
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/kernal_pt_valid_r
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/is_at_hzt_dilation_rgn
add wave -noupdate /tb_kernal_pos_logic_to_phy/dut/is_at_vtc_dilation_rgn
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/hzt_dilation_cnt
add wave -noupdate -radix unsigned /tb_kernal_pos_logic_to_phy/dut/vtc_dilation_cnt
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {11268 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 150
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
WaveRestoreZoom {0 ps} {124551 ps}
