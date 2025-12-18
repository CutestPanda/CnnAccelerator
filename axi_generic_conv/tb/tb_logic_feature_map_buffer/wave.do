onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_logic_feature_map_buffer/dut/aclk
add wave -noupdate /tb_logic_feature_map_buffer/dut/aresetn
add wave -noupdate /tb_logic_feature_map_buffer/dut/aclken
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/fmbufcoln
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/fmbufrown
add wave -noupdate /tb_logic_feature_map_buffer/dut/rst_logic_fmbuf
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_req
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/sfc_rid_to_rplc
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/sfc_row_stored_rd_req_eid
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_stored_vld
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_search_i_req
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/sfc_row_search_i_rid
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_search_o_vld
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/sfc_row_search_o_buf_id
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_search_o_found
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_fin_axis_data
add wave -noupdate -radix binary /tb_logic_feature_map_buffer/dut/s_fin_axis_keep
add wave -noupdate -radix binary /tb_logic_feature_map_buffer/dut/s_fin_axis_user
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_fin_axis_last
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_fin_axis_valid
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_fin_axis_ready
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_rd_req_axis_data
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_rd_req_axis_valid
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_rd_req_axis_ready
add wave -noupdate /tb_logic_feature_map_buffer/dut/m_fout_axis_data
add wave -noupdate /tb_logic_feature_map_buffer/dut/m_fout_axis_user
add wave -noupdate /tb_logic_feature_map_buffer/dut/m_fout_axis_last
add wave -noupdate /tb_logic_feature_map_buffer/dut/m_fout_axis_valid
add wave -noupdate /tb_logic_feature_map_buffer/dut/m_fout_axis_ready
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/m0_fmbuf_cmd_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/m0_fmbuf_cmd_read
add wave -noupdate /tb_logic_feature_map_buffer/dut/m0_fmbuf_cmd_wdata
add wave -noupdate -radix binary /tb_logic_feature_map_buffer/dut/m0_fmbuf_cmd_wmask
add wave -noupdate /tb_logic_feature_map_buffer/dut/m0_fmbuf_cmd_valid
add wave -noupdate /tb_logic_feature_map_buffer/dut/m0_fmbuf_cmd_ready
add wave -noupdate /tb_logic_feature_map_buffer/dut/m0_fmbuf_rsp_rdata
add wave -noupdate /tb_logic_feature_map_buffer/dut/m0_fmbuf_rsp_err
add wave -noupdate /tb_logic_feature_map_buffer/dut/m0_fmbuf_rsp_valid
add wave -noupdate /tb_logic_feature_map_buffer/dut/m0_fmbuf_rsp_ready
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/m1_fmbuf_cmd_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/m1_fmbuf_cmd_read
add wave -noupdate /tb_logic_feature_map_buffer/dut/m1_fmbuf_cmd_wdata
add wave -noupdate -radix binary /tb_logic_feature_map_buffer/dut/m1_fmbuf_cmd_wmask
add wave -noupdate /tb_logic_feature_map_buffer/dut/m1_fmbuf_cmd_valid
add wave -noupdate /tb_logic_feature_map_buffer/dut/m1_fmbuf_cmd_ready
add wave -noupdate /tb_logic_feature_map_buffer/dut/m1_fmbuf_rsp_rdata
add wave -noupdate /tb_logic_feature_map_buffer/dut/m1_fmbuf_rsp_err
add wave -noupdate /tb_logic_feature_map_buffer/dut/m1_fmbuf_rsp_valid
add wave -noupdate /tb_logic_feature_map_buffer/dut/m1_fmbuf_rsp_ready
add wave -noupdate /tb_logic_feature_map_buffer/dut/actual_rid_mp_tb_mem_clk
add wave -noupdate /tb_logic_feature_map_buffer/dut/actual_rid_mp_tb_mem_wen_a
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/actual_rid_mp_tb_mem_addr_a
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/actual_rid_mp_tb_mem_din_a
add wave -noupdate /tb_logic_feature_map_buffer/dut/actual_rid_mp_tb_mem_ren_b
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/actual_rid_mp_tb_mem_addr_b
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/actual_rid_mp_tb_mem_dout_b
add wave -noupdate /tb_logic_feature_map_buffer/dut/buffer_rid_mp_tb_mem_clk
add wave -noupdate /tb_logic_feature_map_buffer/dut/buffer_rid_mp_tb_mem_wen_a
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/buffer_rid_mp_tb_mem_addr_a
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/buffer_rid_mp_tb_mem_din_a
add wave -noupdate /tb_logic_feature_map_buffer/dut/buffer_rid_mp_tb_mem_ren_b
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/buffer_rid_mp_tb_mem_addr_b
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/buffer_rid_mp_tb_mem_dout_b
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_activate_req
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/wtfm_activate_rid
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_rplc_req
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/rdfm_rplc_rid
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_sts
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/wt_fmbuf_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/wt_fmbuf_bus_cmd_fns
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/wt_fmbuf_trans_sfc
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_rid
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_rd_req_axis_data_auto_rplc
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/s_rd_req_axis_data_rid
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/s_rd_req_axis_data_start_sfc_id
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/s_rd_req_axis_data_sfc_n
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_sts
add wave -noupdate /tb_logic_feature_map_buffer/dut/rd_fmbuf_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/auto_rplc_sfc_row_after_rd
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_rid_to_rd
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_n_to_rd
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_rd_cmd_n_sent
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_rd_resp_n_recv
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {6511980 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 199
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
WaveRestoreZoom {17083559 ps} {19037708 ps}
