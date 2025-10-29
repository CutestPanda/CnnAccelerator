onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/aclk
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/aresetn
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/aclken
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/calfmt
add wave -noupdate -expand -group dut -radix unsigned /tb_conv_middle_res_acmlt_buf/dut/ofmw_sub1
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/s_axis_mid_res_data
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/s_axis_mid_res_keep
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/s_axis_mid_res_user
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/s_axis_mid_res_valid
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/s_axis_mid_res_ready
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/m_axis_fnl_res_data
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/m_axis_fnl_res_keep
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/m_axis_fnl_res_last
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/m_axis_fnl_res_valid
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/m_axis_fnl_res_ready
add wave -noupdate -expand -group dut -radix unsigned /tb_conv_middle_res_acmlt_buf/dut/mid_res_upd_pipl_sts
add wave -noupdate -expand -group dut -radix unsigned /tb_conv_middle_res_acmlt_buf/dut/mid_res_upd_pipl_bid
add wave -noupdate -expand -group dut -radix unsigned /tb_conv_middle_res_acmlt_buf/dut/mid_res_upd_pipl_cid
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_filled
add wave -noupdate -expand -group dut -radix unsigned /tb_conv_middle_res_acmlt_buf/dut/col_cnt_at_wr
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_wen_at_wr
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_wen_at_wr_d4
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_wen_at_wr_d11
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_ren_at_wr
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_full_n
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_wptr_at_wr
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_rptr_at_wr
add wave -noupdate -expand -group dut -radix unsigned /tb_conv_middle_res_acmlt_buf/dut/col_cnt_at_rd
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_wen_at_rd
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_ren_at_rd
add wave -noupdate -expand -group dut /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_empty_n
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_wptr_at_rd
add wave -noupdate -expand -group dut -radix binary /tb_conv_middle_res_acmlt_buf/dut/mid_res_line_buf_rptr_at_rd
add wave -noupdate -group mem_0 {/tb_conv_middle_res_acmlt_buf/mem_blk[0]/bram_u/clk}
add wave -noupdate -group mem_0 {/tb_conv_middle_res_acmlt_buf/mem_blk[0]/bram_u/wen_a}
add wave -noupdate -group mem_0 -radix unsigned {/tb_conv_middle_res_acmlt_buf/mem_blk[0]/bram_u/addr_a}
add wave -noupdate -group mem_0 {/tb_conv_middle_res_acmlt_buf/mem_blk[0]/bram_u/din_a}
add wave -noupdate -group mem_0 {/tb_conv_middle_res_acmlt_buf/mem_blk[0]/bram_u/ren_b}
add wave -noupdate -group mem_0 -radix unsigned {/tb_conv_middle_res_acmlt_buf/mem_blk[0]/bram_u/addr_b}
add wave -noupdate -group mem_0 {/tb_conv_middle_res_acmlt_buf/mem_blk[0]/bram_u/dout_b}
add wave -noupdate -group mem_1 {/tb_conv_middle_res_acmlt_buf/mem_blk[1]/bram_u/clk}
add wave -noupdate -group mem_1 {/tb_conv_middle_res_acmlt_buf/mem_blk[1]/bram_u/wen_a}
add wave -noupdate -group mem_1 -radix unsigned {/tb_conv_middle_res_acmlt_buf/mem_blk[1]/bram_u/addr_a}
add wave -noupdate -group mem_1 {/tb_conv_middle_res_acmlt_buf/mem_blk[1]/bram_u/din_a}
add wave -noupdate -group mem_1 {/tb_conv_middle_res_acmlt_buf/mem_blk[1]/bram_u/ren_b}
add wave -noupdate -group mem_1 -radix unsigned {/tb_conv_middle_res_acmlt_buf/mem_blk[1]/bram_u/addr_b}
add wave -noupdate -group mem_1 {/tb_conv_middle_res_acmlt_buf/mem_blk[1]/bram_u/dout_b}
add wave -noupdate -group mem_2 {/tb_conv_middle_res_acmlt_buf/mem_blk[2]/bram_u/clk}
add wave -noupdate -group mem_2 {/tb_conv_middle_res_acmlt_buf/mem_blk[2]/bram_u/wen_a}
add wave -noupdate -group mem_2 -radix unsigned {/tb_conv_middle_res_acmlt_buf/mem_blk[2]/bram_u/addr_a}
add wave -noupdate -group mem_2 {/tb_conv_middle_res_acmlt_buf/mem_blk[2]/bram_u/din_a}
add wave -noupdate -group mem_2 {/tb_conv_middle_res_acmlt_buf/mem_blk[2]/bram_u/ren_b}
add wave -noupdate -group mem_2 -radix unsigned {/tb_conv_middle_res_acmlt_buf/mem_blk[2]/bram_u/addr_b}
add wave -noupdate -group mem_2 {/tb_conv_middle_res_acmlt_buf/mem_blk[2]/bram_u/dout_b}
add wave -noupdate -group mem_3 {/tb_conv_middle_res_acmlt_buf/mem_blk[3]/bram_u/clk}
add wave -noupdate -group mem_3 {/tb_conv_middle_res_acmlt_buf/mem_blk[3]/bram_u/wen_a}
add wave -noupdate -group mem_3 -radix unsigned {/tb_conv_middle_res_acmlt_buf/mem_blk[3]/bram_u/addr_a}
add wave -noupdate -group mem_3 {/tb_conv_middle_res_acmlt_buf/mem_blk[3]/bram_u/din_a}
add wave -noupdate -group mem_3 {/tb_conv_middle_res_acmlt_buf/mem_blk[3]/bram_u/ren_b}
add wave -noupdate -group mem_3 -radix unsigned {/tb_conv_middle_res_acmlt_buf/mem_blk[3]/bram_u/addr_b}
add wave -noupdate -group mem_3 {/tb_conv_middle_res_acmlt_buf/mem_blk[3]/bram_u/dout_b}
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {144585 ps} 0}
quietly wave cursor active 1
configure wave -namecolwidth 238
configure wave -valuecolwidth 87
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
WaveRestoreZoom {98206 ps} {397403 ps}
