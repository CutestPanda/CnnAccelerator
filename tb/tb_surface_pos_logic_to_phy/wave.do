onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/aclk
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/aresetn
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/aclken
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/ext_j_right
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/ext_i_bottom
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/external_padding_left
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/external_padding_top
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/inner_padding_top_bottom
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/inner_padding_left_right
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/blk_start
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/blk_idle
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/blk_i_logic_x
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/blk_i_logic_y
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/blk_done
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/blk_o_phy_x
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/blk_o_phy_y
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/blk_o_is_vld
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/s_div_axis_data
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/s_div_axis_valid
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/s_div_axis_ready
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/m_div_axis_data
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/m_div_axis_valid
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/m_div_axis_ready
add wave -noupdate -radix binary /tb_surface_pos_logic_to_phy/dut/cvt_sts
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/logic_x_latched
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/logic_y_latched
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/is_pt_at_ext_padding_rgn_n
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/phy_x
add wave -noupdate -radix unsigned /tb_surface_pos_logic_to_phy/dut/phy_y
add wave -noupdate /tb_surface_pos_logic_to_phy/dut/pt_vld
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {5630000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 206
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
WaveRestoreZoom {5464560 ps} {5708413 ps}
