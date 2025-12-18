onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_conv_data_sfc_gen/dut/aclk
add wave -noupdate /tb_conv_data_sfc_gen/dut/aresetn
add wave -noupdate /tb_conv_data_sfc_gen/dut/aclken
add wave -noupdate -radix unsigned /tb_conv_data_sfc_gen/dut/s_stream_axis_data
add wave -noupdate -radix binary /tb_conv_data_sfc_gen/dut/s_stream_axis_keep
add wave -noupdate /tb_conv_data_sfc_gen/dut/s_stream_axis_user
add wave -noupdate /tb_conv_data_sfc_gen/dut/s_stream_axis_last
add wave -noupdate /tb_conv_data_sfc_gen/dut/s_stream_axis_valid
add wave -noupdate /tb_conv_data_sfc_gen/dut/s_stream_axis_ready
add wave -noupdate /tb_conv_data_sfc_gen/dut/m_sfc_axis_data
add wave -noupdate -radix binary /tb_conv_data_sfc_gen/dut/m_sfc_axis_keep
add wave -noupdate -radix unsigned /tb_conv_data_sfc_gen/dut/m_sfc_axis_user
add wave -noupdate /tb_conv_data_sfc_gen/dut/m_sfc_axis_last
add wave -noupdate /tb_conv_data_sfc_gen/dut/m_sfc_axis_valid
add wave -noupdate /tb_conv_data_sfc_gen/dut/m_sfc_axis_ready
add wave -noupdate /tb_conv_data_sfc_gen/dut/first_trans_within_strm
add wave -noupdate -radix binary /tb_conv_data_sfc_gen/dut/cur_strm_trans_hw_vld
add wave -noupdate -radix unsigned /tb_conv_data_sfc_gen/dut/vld_hw_n_of_cur_strm_trans
add wave -noupdate /tb_conv_data_sfc_gen/dut/cur_strm_trans_bufferable
add wave -noupdate /tb_conv_data_sfc_gen/dut/strm_pkt_msg_fifo_wen
add wave -noupdate /tb_conv_data_sfc_gen/dut/strm_pkt_msg_fifo_din
add wave -noupdate /tb_conv_data_sfc_gen/dut/strm_pkt_msg_fifo_full_n
add wave -noupdate /tb_conv_data_sfc_gen/dut/strm_pkt_msg_fifo_ren
add wave -noupdate /tb_conv_data_sfc_gen/dut/strm_pkt_msg_fifo_dout
add wave -noupdate /tb_conv_data_sfc_gen/dut/strm_pkt_msg_fifo_empty_n
add wave -noupdate /tb_conv_data_sfc_gen/dut/hw_buf_data
add wave -noupdate /tb_conv_data_sfc_gen/dut/hw_buf_last
add wave -noupdate -radix unsigned /tb_conv_data_sfc_gen/dut/hw_stored_cnt
add wave -noupdate -radix unsigned /tb_conv_data_sfc_gen/dut/hw_buf_wptr
add wave -noupdate -radix unsigned /tb_conv_data_sfc_gen/dut/hw_buf_rptr
add wave -noupdate -radix binary /tb_conv_data_sfc_gen/dut/hw_buf_wen
add wave -noupdate /tb_conv_data_sfc_gen/dut/hw_buf_wdata
add wave -noupdate /tb_conv_data_sfc_gen/dut/hw_buf_rdata
add wave -noupdate -radix binary /tb_conv_data_sfc_gen/dut/hw_buf_rlast
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {129485 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 202
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
WaveRestoreZoom {81570 ps} {353470 ps}
