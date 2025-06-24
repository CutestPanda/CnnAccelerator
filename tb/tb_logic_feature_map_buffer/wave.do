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
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_pending
add wave -noupdate /tb_logic_feature_map_buffer/dut/init_fns
add wave -noupdate /tb_logic_feature_map_buffer/dut/s_fin_axis_data
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/s_fin_axis_user
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
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_vld_flag_mem_clk
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_vld_flag_mem_en
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_vld_flag_mem_wen
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/sfc_row_vld_flag_mem_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_vld_flag_mem_din
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_vld_flag_mem_dout
add wave -noupdate /tb_logic_feature_map_buffer/dut/init_vld_flag_en
add wave -noupdate /tb_logic_feature_map_buffer/dut/init_vld_flag_wen
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/init_vld_flag_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/init_vld_flag_din
add wave -noupdate /tb_logic_feature_map_buffer/dut/init_vld_flag_fns
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_access_en
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_access_wen
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_access_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_access_din
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_access_dout
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_access_en
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_access_wen
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_access_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_access_din
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_access_dout
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_access_en
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_access_wen
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_access_addr
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_access_din
add wave -noupdate /tb_logic_feature_map_buffer/dut/init_vld_flag_req
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_access_req
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_access_req
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_access_req
add wave -noupdate /tb_logic_feature_map_buffer/dut/init_vld_flag_granted
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_access_granted
add wave -noupdate /tb_logic_feature_map_buffer/dut/rdfm_access_granted
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_access_granted
add wave -noupdate /tb_logic_feature_map_buffer/dut/sfc_row_rplc_access_pending
add wave -noupdate /tb_logic_feature_map_buffer/dut/on_sfc_row_rplc
add wave -noupdate -radix unsigned /tb_logic_feature_map_buffer/dut/on_sfc_rplc_rid
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_sts
add wave -noupdate /tb_logic_feature_map_buffer/dut/wtfm_query_vld_flag_available_n
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
WaveRestoreCursors {{Cursor 1} {7091000 ps} 0}
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
WaveRestoreZoom {6104853 ps} {8077147 ps}
