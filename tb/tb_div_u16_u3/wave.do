onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_div_u16_u3/dut/aclk
add wave -noupdate /tb_div_u16_u3/dut/aresetn
add wave -noupdate /tb_div_u16_u3/dut/aclken
add wave -noupdate /tb_div_u16_u3/dut/s_axis_data
add wave -noupdate /tb_div_u16_u3/dut/s_axis_valid
add wave -noupdate /tb_div_u16_u3/dut/s_axis_ready
add wave -noupdate /tb_div_u16_u3/dut/m_axis_data
add wave -noupdate /tb_div_u16_u3/dut/m_axis_valid
add wave -noupdate /tb_div_u16_u3/dut/m_axis_ready
add wave -noupdate -radix unsigned /tb_div_u16_u3/dut/dividend
add wave -noupdate -radix unsigned /tb_div_u16_u3/dut/cmp
add wave -noupdate -radix unsigned /tb_div_u16_u3/dut/quotient
add wave -noupdate -radix unsigned /tb_div_u16_u3/dut/divisor_lsh_n
add wave -noupdate -radix binary /tb_div_u16_u3/dut/cal_sts
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
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
WaveRestoreZoom {0 ps} {1 ns}
