onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate /tb_logic_kernal_buffer/dut/aclk
add wave -noupdate /tb_logic_kernal_buffer/dut/aresetn
add wave -noupdate /tb_logic_kernal_buffer/dut/aclken
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/kbufgrpn
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/kbufgrpsz
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/cgrpn
add wave -noupdate /tb_logic_kernal_buffer/dut/rst_logic_kbuf
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/sw_rgn_rplc
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/rsv_rgn_vld_grpn
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/sw_rgn_vld
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/sw_rgn0_grpid
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/sw_rgn1_grpid
add wave -noupdate /tb_logic_kernal_buffer/dut/has_sw_rgn
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/s_in_cgrp_axis_data
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/s_in_cgrp_axis_keep
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/s_in_cgrp_axis_user
add wave -noupdate /tb_logic_kernal_buffer/dut/s_in_cgrp_axis_last
add wave -noupdate /tb_logic_kernal_buffer/dut/s_in_cgrp_axis_valid
add wave -noupdate /tb_logic_kernal_buffer/dut/s_in_cgrp_axis_ready
add wave -noupdate /tb_logic_kernal_buffer/dut/s_rd_req_axis_data
add wave -noupdate /tb_logic_kernal_buffer/dut/s_rd_req_axis_valid
add wave -noupdate /tb_logic_kernal_buffer/dut/s_rd_req_axis_ready
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/m_out_wgtblk_axis_data
add wave -noupdate /tb_logic_kernal_buffer/dut/m_out_wgtblk_axis_user
add wave -noupdate /tb_logic_kernal_buffer/dut/m_out_wgtblk_axis_last
add wave -noupdate /tb_logic_kernal_buffer/dut/m_out_wgtblk_axis_valid
add wave -noupdate /tb_logic_kernal_buffer/dut/m_out_wgtblk_axis_ready
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/m0_kbuf_cmd_addr
add wave -noupdate /tb_logic_kernal_buffer/dut/m0_kbuf_cmd_read
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/m0_kbuf_cmd_wdata
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/m0_kbuf_cmd_wmask
add wave -noupdate /tb_logic_kernal_buffer/dut/m0_kbuf_cmd_valid
add wave -noupdate /tb_logic_kernal_buffer/dut/m0_kbuf_cmd_ready
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/m0_kbuf_rsp_rdata
add wave -noupdate /tb_logic_kernal_buffer/dut/m0_kbuf_rsp_err
add wave -noupdate /tb_logic_kernal_buffer/dut/m0_kbuf_rsp_valid
add wave -noupdate /tb_logic_kernal_buffer/dut/m0_kbuf_rsp_ready
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/m1_kbuf_cmd_addr
add wave -noupdate /tb_logic_kernal_buffer/dut/m1_kbuf_cmd_read
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/m1_kbuf_cmd_wdata
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/m1_kbuf_cmd_wmask
add wave -noupdate /tb_logic_kernal_buffer/dut/m1_kbuf_cmd_valid
add wave -noupdate /tb_logic_kernal_buffer/dut/m1_kbuf_cmd_ready
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/m1_kbuf_rsp_rdata
add wave -noupdate /tb_logic_kernal_buffer/dut/m1_kbuf_rsp_err
add wave -noupdate /tb_logic_kernal_buffer/dut/m1_kbuf_rsp_valid
add wave -noupdate /tb_logic_kernal_buffer/dut/m1_kbuf_rsp_ready
add wave -noupdate /tb_logic_kernal_buffer/dut/wt_rsv_rgn_actual_gid_mismatch
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/kernal_blk_addr_stride
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/kernal_blk_addr_stride_lshn
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/kbufgrpn_sub1
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/wtblkn_in_cgrp
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/sw_rgn0_baseaddr
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/sw_rgn1_baseaddr
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/rsv_rgn_vld_grpn_r
add wave -noupdate /tb_logic_kernal_buffer/dut/rsv_rgn_wen
add wave -noupdate /tb_logic_kernal_buffer/dut/sw_rgn0_vld_r
add wave -noupdate /tb_logic_kernal_buffer/dut/sw_rgn1_vld_r
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/sw_rgn0_grpid_r
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/sw_rgn1_grpid_r
add wave -noupdate /tb_logic_kernal_buffer/dut/sw_rgn0_wen
add wave -noupdate /tb_logic_kernal_buffer/dut/sw_rgn1_wen
add wave -noupdate /tb_logic_kernal_buffer/dut/on_auto_rplc_sw_rgn0
add wave -noupdate /tb_logic_kernal_buffer/dut/on_auto_rplc_sw_rgn1
add wave -noupdate /tb_logic_kernal_buffer/dut/s_in_cgrp_axis_user_last_blk
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/s_in_cgrp_axis_user_actual_gid
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/in_cgrp_sfc_data_mask
add wave -noupdate /tb_logic_kernal_buffer/dut/rsv_rgn_full
add wave -noupdate /tb_logic_kernal_buffer/dut/in_cgrp_passing
add wave -noupdate /tb_logic_kernal_buffer/dut/in_cgrp_store_to_rsv_rgn
add wave -noupdate /tb_logic_kernal_buffer/dut/in_cgrp_store_to_sw_rgn0
add wave -noupdate /tb_logic_kernal_buffer/dut/in_cgrp_store_to_sw_rgn1
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/kbuf_to_wt_cgrp_baseaddr
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/kbuf_to_wt_cgrp_ofsaddr
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/rsv_rgn_to_wt_cgrp_baseaddr
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/onroad_kbuf_wt_sfc_n
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/onroad_kbuf_wt_sfc_n_nxt
add wave -noupdate /tb_logic_kernal_buffer/dut/submit_wt_cgrp_pending
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/submit_wt_cgrp_actual_gid
add wave -noupdate /tb_logic_kernal_buffer/dut/wt_rsv_rgn_actual_gid_mismatch_r
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/s_rd_req_axis_data_sfc_to_rd
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/s_rd_req_axis_data_bid
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/s_rd_req_axis_data_actual_gid
add wave -noupdate /tb_logic_kernal_buffer/dut/s_rd_req_axis_data_auto_rplc_sw_rgn
add wave -noupdate /tb_logic_kernal_buffer/dut/find_wtblk_in_rsv_rgn
add wave -noupdate /tb_logic_kernal_buffer/dut/find_wtblk_in_sw_rgn0
add wave -noupdate /tb_logic_kernal_buffer/dut/find_wtblk_in_sw_rgn1
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/rd_wtblk_baseaddr
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/wtblk_to_rd_sfc_n
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/sfc_rd_cmd_dsptc_n
add wave -noupdate -radix unsigned /tb_logic_kernal_buffer/dut/sfc_rd_resp_acpt_n
add wave -noupdate -radix binary /tb_logic_kernal_buffer/dut/rd_wtblk_sts
add wave -noupdate /tb_logic_kernal_buffer/dut/auto_rplc_sw_rgn0
add wave -noupdate /tb_logic_kernal_buffer/dut/auto_rplc_sw_rgn1
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {931000 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 229
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
WaveRestoreZoom {705258 ps} {847160 ps}
