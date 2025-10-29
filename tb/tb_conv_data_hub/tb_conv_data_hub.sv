import uvm_pkg::*;
import tue_pkg::*;
import panda_pkg::*;

`include "uvm_macros.svh"
`include "tue_macros.svh"
`include "panda_macros.svh"

`include "panda_ext_defines.svh"
`include "panda_ext_cfg.svh"
`include "panda_data_obj.svh"
`include "panda_ext_trans.svh"

`include "panda_ext_scoreboard.svh"

`include "panda_test.svh"

module tb_conv_data_hub();
	
	/** 常量 **/
	// 每个表面行的表面个数类型编码
	localparam FMBUFCOLN_4 = 4'b0000;
	localparam FMBUFCOLN_8 = 4'b0001;
	localparam FMBUFCOLN_16 = 4'b0010;
	localparam FMBUFCOLN_32 = 4'b0011;
	localparam FMBUFCOLN_64 = 4'b0100;
	localparam FMBUFCOLN_128 = 4'b0101;
	localparam FMBUFCOLN_256 = 4'b0110;
	localparam FMBUFCOLN_512 = 4'b0111;
	localparam FMBUFCOLN_1024 = 4'b1000;
	localparam FMBUFCOLN_2048 = 4'b1001;
	localparam FMBUFCOLN_4096 = 4'b1010;
	// 每个通道组的权重块个数的类型编码
	localparam KBUFGRPSZ_1 = 3'b000; // 1x1
	localparam KBUFGRPSZ_9 = 3'b001; // 3x3
	localparam KBUFGRPSZ_25 = 3'b010; // 5x5
	localparam KBUFGRPSZ_49 = 3'b011; // 7x7
	localparam KBUFGRPSZ_81 = 3'b100; // 9x9
	localparam KBUFGRPSZ_121 = 3'b101; // 11x11
	// 每个权重块的表面个数的类型编码
	localparam WGTBLK_SFC_N_1 = 3'b000; // 1个表面
	localparam WGTBLK_SFC_N_2 = 3'b001; // 2个表面
	localparam WGTBLK_SFC_N_4 = 3'b010; // 4个表面
	localparam WGTBLK_SFC_N_8 = 3'b011; // 8个表面
	localparam WGTBLK_SFC_N_16 = 3'b100; // 16个表面
	localparam WGTBLK_SFC_N_32 = 3'b101; // 32个表面
	localparam WGTBLK_SFC_N_64 = 3'b110; // 64个表面
	localparam WGTBLK_SFC_N_128 = 3'b111; // 128个表面
	
	/** 函数 **/
	// 计算bit_depth的最高有效位编号(即位数-1)
    function integer clogb2(input integer bit_depth);
    begin
		if(bit_depth == 0)
			clogb2 = 0;
		else
		begin
			for(clogb2 = -1;bit_depth > 0;clogb2 = clogb2 + 1)
				bit_depth = bit_depth >> 1;
		end
    end
    endfunction
	
	/** 配置参数 **/
	parameter integer STREAM_DATA_WIDTH = 32; // DMA数据流的位宽(32 | 64 | 128 | 256)
	parameter integer ATOMIC_C = 4; // 通道并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer ATOMIC_K = 8; // 核并行数(1 | 2 | 4 | 8 | 16 | 32)
	parameter integer CBUF_BANK_N = 16; // 物理缓存的MEM片数(4 | 8 | 16 | 32 | 64 | 128)
	parameter integer CBUF_DEPTH_FOREACH_BANK = 4096; // 物理缓存每片MEM的深度(128 | 256 | 512 | 1024 | 2048 | 4096 | 8192)
	parameter integer FM_RD_REQ_PRE_ACPT_N = 4; // 可提前接受的特征图读请求个数(1 | 2 | 4 | 8 | 16)
	parameter integer KWGTBLK_RD_REQ_PRE_ACPT_N = 4; // 可提前接受的卷积核权重块读请求个数(1 | 2 | 4 | 8 | 16)
	parameter integer MAX_FMBUF_ROWN = 32; // 特征图缓存的最大表面行数(8 | 16 | 32 | 64 | 128 | 256 | 512 | 1024)
	parameter integer LG_FMBUF_BUFFER_RID_WIDTH = clogb2(MAX_FMBUF_ROWN); // 特征图缓存的缓存行号的位宽(3~10, 应为clogb2(MAX_FMBUF_ROWN))
	parameter bit[3:0] FMBUFCOLN = FMBUFCOLN_64; // 每个表面行的表面个数类型
	parameter bit[9:0] FMBUFROWN = 10 - 1; // 可缓存的表面行数 - 1
	parameter bit GRP_CONV_BUF_MODE = 1'b0; // 是否处于组卷积缓存模式
	parameter bit[2:0] KBUFGRPSZ = KBUFGRPSZ_9; // 每个通道组的权重块个数的类型
	parameter bit[2:0] SFC_N_EACH_WGTBLK = WGTBLK_SFC_N_16; // 每个权重块的表面个数的类型
	parameter bit[7:0] KBUFGRPN = 10 - 1; // 可缓存的通道组数 - 1
	parameter bit[7:0] FMBUFBANKN = 8; // 分配给特征图缓存的Bank数
	
	/** 接口 **/
	panda_clock_if clk_if();
	panda_reset_if rst_if(clk_if.clk_p);
	panda_axis_if fm_rd_req_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if kwgtblk_rd_req_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if fm_fout_axis_s(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if kout_wgtblk_axis_s(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma0_strm_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma1_strm_axis_m(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma0_cmd_axis_s(clk_if.clk_p, rst_if.reset_n);
	panda_axis_if dma1_cmd_axis_s(clk_if.clk_p, rst_if.reset_n);
	
	/** 主任务 **/
	initial begin
		ConvDataHubCfg test_cfg;
		FmapBuilder fmap_builder;
		KernalSetBuilder kernal_builder;
		PandaMemoryAdapter fmap_mem_adpt;
		PandaMemoryAdapter kernal_mem_adpt;
		Fmap fmap;
		KernalSet kernal_set;
		
		test_cfg = new();
		test_cfg.randomize() with{
			stream_data_width == STREAM_DATA_WIDTH;
			atomic_c == ATOMIC_C;
			atomic_k == ATOMIC_K;
			
			fmbufcoln == FMBUFCOLN;
			fmbufrown == (FMBUFROWN + 1);
			
			grp_conv_buf_mode == GRP_CONV_BUF_MODE;
			kernal_shape == KBUFGRPSZ;
			sfc_n_each_wgtblk == SFC_N_EACH_WGTBLK;
			kbufgrpn == (KBUFGRPN + 1);
			
			fmap_mem_baseaddr == 1024;
			total_fmrow_n == 16;
			fmrow_len == 8;
			
			foreach(actual_sfc_rid_foreach_fmrow[i]){
				actual_sfc_rid_foreach_fmrow[i] == (i + 100);
			}
			
			kernal_mem_baseaddr == 1024;
			total_kernal_set_n == 4;
			total_cgrp_n == 50;
			cgrpn_foreach_kernal_set[0] == 20;
			cgrpn_foreach_kernal_set[1] == 10;
			cgrpn_foreach_kernal_set[2] == 11;
			cgrpn_foreach_kernal_set[3] == 9;
		};
		
		test_cfg.print();
		
		fmap_builder = new();
		fmap_builder.build_default_feature_map(test_cfg);
		fmap = fmap_builder.get_feature_map();
		
		kernal_builder = new();
		kernal_builder.build_default_kernal_set(test_cfg);
		kernal_set = kernal_builder.get_kernal_set();
		
		fmap_mem_adpt = new(fmap, "FmapPandaMemoryAdapter", test_cfg.stream_data_width);
		kernal_mem_adpt = new(kernal_set, "KernalPandaMemoryAdapter", test_cfg.stream_data_width);
		
		uvm_config_db #(ConvDataHubCfg)::set(null, "", "test_cfg", test_cfg);
		uvm_config_db #(PandaMemoryAdapter)::set(null, "", "fmap_mem", fmap_mem_adpt);
		uvm_config_db #(PandaMemoryAdapter)::set(null, "", "kernal_mem", kernal_mem_adpt);
		
		uvm_config_db #(panda_clock_vif)::set(null, "", "clk_vif", clk_if);
		uvm_config_db #(panda_reset_vif)::set(null, "", "rst_vif", rst_if);
		
		uvm_config_db #(panda_axis_vif)::set(null, "", "fm_rd_req_axis_vif_m", fm_rd_req_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "kwgtblk_rd_req_axis_vif_m", kwgtblk_rd_req_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "fm_fout_axis_vif_s", fm_fout_axis_s);
		uvm_config_db #(panda_axis_vif)::set(null, "", "kout_wgtblk_axis_vif_s", kout_wgtblk_axis_s);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma0_strm_axis_vif_m", dma0_strm_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma1_strm_axis_vif_m", dma1_strm_axis_m);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma0_cmd_axis_vif_s", dma0_cmd_axis_s);
		uvm_config_db #(panda_axis_vif)::set(null, "", "dma1_cmd_axis_vif_s", dma1_cmd_axis_s);
		
		run_test("conv_data_hub_test");
	end
	
	/** 待测模块 **/
	// 特征图表面行读请求(AXIS从机)
	wire[103:0] s_fm_rd_req_axis_data;
	wire s_fm_rd_req_axis_valid;
	wire s_fm_rd_req_axis_ready;
	// 卷积核权重块读请求(AXIS从机)
	wire[103:0] s_kwgtblk_rd_req_axis_data;
	wire s_kwgtblk_rd_req_axis_valid;
	wire s_kwgtblk_rd_req_axis_ready;
	// 特征图表面行数据输出(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_fm_fout_axis_data;
	wire m_fm_fout_axis_last; // 标志本次读请求的最后1个表面
	wire m_fm_fout_axis_valid;
	wire m_fm_fout_axis_ready;
	// 卷积核权重块数据输出(AXIS主机)
	wire[ATOMIC_C*2*8-1:0] m_kout_wgtblk_axis_data;
	wire m_kout_wgtblk_axis_last; // 标志本次读请求的最后1个表面
	wire m_kout_wgtblk_axis_valid;
	wire m_kout_wgtblk_axis_ready;
	// DMA(MM2S方向)命令流#0(AXIS主机)
	wire[55:0] m0_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m0_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m0_dma_cmd_axis_last; // 帧尾标志
	wire m0_dma_cmd_axis_valid;
	wire m0_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流#0(AXIS从机)
	wire[STREAM_DATA_WIDTH-1:0] s0_dma_strm_axis_data;
	wire[STREAM_DATA_WIDTH/8-1:0] s0_dma_strm_axis_keep;
	wire s0_dma_strm_axis_last;
	wire s0_dma_strm_axis_valid;
	wire s0_dma_strm_axis_ready;
	// DMA(MM2S方向)命令流#1(AXIS主机)
	wire[55:0] m1_dma_cmd_axis_data; // {待传输字节数(24bit), 传输首地址(32bit)}
	wire m1_dma_cmd_axis_user; // {固定(1'b1)/递增(1'b0)传输(1bit)}
	wire m1_dma_cmd_axis_last; // 帧尾标志
	wire m1_dma_cmd_axis_valid;
	wire m1_dma_cmd_axis_ready;
	// DMA(MM2S方向)数据流#1(AXIS从机)
	wire[STREAM_DATA_WIDTH-1:0] s1_dma_strm_axis_data;
	wire[STREAM_DATA_WIDTH/8-1:0] s1_dma_strm_axis_keep;
	wire s1_dma_strm_axis_last;
	wire s1_dma_strm_axis_valid;
	wire s1_dma_strm_axis_ready;
	// 实际表面行号映射表MEM主接口
	wire actual_rid_mp_tb_mem_clk;
	wire actual_rid_mp_tb_mem_wen_a;
	wire[11:0] actual_rid_mp_tb_mem_addr_a;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_din_a;
	wire actual_rid_mp_tb_mem_ren_b;
	wire[11:0] actual_rid_mp_tb_mem_addr_b;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] actual_rid_mp_tb_mem_dout_b;
	// 缓存行号映射表MEM主接口
	wire buffer_rid_mp_tb_mem_clk;
	wire buffer_rid_mp_tb_mem_wen_a;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_a;
	wire[11:0] buffer_rid_mp_tb_mem_din_a;
	wire buffer_rid_mp_tb_mem_ren_b;
	wire[LG_FMBUF_BUFFER_RID_WIDTH-1:0] buffer_rid_mp_tb_mem_addr_b;
	wire[11:0] buffer_rid_mp_tb_mem_dout_b;
	// 物理缓存的MEM主接口
	wire phy_conv_buf_mem_clk_a;
	wire[CBUF_BANK_N-1:0] phy_conv_buf_mem_en_a;
	wire[CBUF_BANK_N*ATOMIC_C*2-1:0] phy_conv_buf_mem_wen_a;
	wire[CBUF_BANK_N*16-1:0] phy_conv_buf_mem_addr_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_din_a;
	wire[CBUF_BANK_N*ATOMIC_C*2*8-1:0] phy_conv_buf_mem_dout_a;
	
	assign s_fm_rd_req_axis_data = fm_rd_req_axis_m.data[103:0];
	assign s_fm_rd_req_axis_valid = fm_rd_req_axis_m.valid;
	assign fm_rd_req_axis_m.ready = s_fm_rd_req_axis_ready;
	
	assign s_kwgtblk_rd_req_axis_data = kwgtblk_rd_req_axis_m.data[103:0];
	assign s_kwgtblk_rd_req_axis_valid = kwgtblk_rd_req_axis_m.valid;
	assign kwgtblk_rd_req_axis_m.ready = s_kwgtblk_rd_req_axis_ready;
	
	assign fm_fout_axis_s.data[ATOMIC_C*2*8-1:0] = m_fm_fout_axis_data;
	assign fm_fout_axis_s.last = m_fm_fout_axis_last;
	assign fm_fout_axis_s.valid = m_fm_fout_axis_valid;
	assign m_fm_fout_axis_ready = fm_fout_axis_s.ready;
	
	assign kout_wgtblk_axis_s.data[ATOMIC_C*2*8-1:0] = m_kout_wgtblk_axis_data;
	assign kout_wgtblk_axis_s.last = m_kout_wgtblk_axis_last;
	assign kout_wgtblk_axis_s.valid = m_kout_wgtblk_axis_valid;
	assign m_kout_wgtblk_axis_ready = kout_wgtblk_axis_s.ready;
	
	assign dma0_cmd_axis_s.data[55:0] = m0_dma_cmd_axis_data;
	assign dma0_cmd_axis_s.user[0] = m0_dma_cmd_axis_user;
	assign dma0_cmd_axis_s.last = m0_dma_cmd_axis_last;
	assign dma0_cmd_axis_s.valid = m0_dma_cmd_axis_valid;
	assign m0_dma_cmd_axis_ready = dma0_cmd_axis_s.ready;
	
	assign s0_dma_strm_axis_data = dma0_strm_axis_m.data[STREAM_DATA_WIDTH-1:0];
	assign s0_dma_strm_axis_keep = dma0_strm_axis_m.keep[STREAM_DATA_WIDTH/8-1:0];
	assign s0_dma_strm_axis_last = dma0_strm_axis_m.last;
	assign s0_dma_strm_axis_valid = dma0_strm_axis_m.valid;
	assign dma0_strm_axis_m.ready = s0_dma_strm_axis_ready;
	
	assign dma1_cmd_axis_s.data[55:0] = m1_dma_cmd_axis_data;
	assign dma1_cmd_axis_s.user[0] = m1_dma_cmd_axis_user;
	assign dma1_cmd_axis_s.last = m1_dma_cmd_axis_last;
	assign dma1_cmd_axis_s.valid = m1_dma_cmd_axis_valid;
	assign m1_dma_cmd_axis_ready = dma1_cmd_axis_s.ready;
	
	assign s1_dma_strm_axis_data = dma1_strm_axis_m.data[STREAM_DATA_WIDTH-1:0];
	assign s1_dma_strm_axis_keep = dma1_strm_axis_m.keep[STREAM_DATA_WIDTH/8-1:0];
	assign s1_dma_strm_axis_last = dma1_strm_axis_m.last;
	assign s1_dma_strm_axis_valid = dma1_strm_axis_m.valid;
	assign dma1_strm_axis_m.ready = s1_dma_strm_axis_ready;
	
	conv_data_hub #(
		.STREAM_DATA_WIDTH(STREAM_DATA_WIDTH),
		.ATOMIC_C(ATOMIC_C),
		.ATOMIC_K(ATOMIC_K),
		.CBUF_BANK_N(CBUF_BANK_N),
		.CBUF_DEPTH_FOREACH_BANK(CBUF_DEPTH_FOREACH_BANK),
		.FM_RD_REQ_PRE_ACPT_N(FM_RD_REQ_PRE_ACPT_N),
		.KWGTBLK_RD_REQ_PRE_ACPT_N(KWGTBLK_RD_REQ_PRE_ACPT_N),
		.MAX_FMBUF_ROWN(MAX_FMBUF_ROWN),
		.LG_FMBUF_BUFFER_RID_WIDTH(LG_FMBUF_BUFFER_RID_WIDTH),
		.SIM_DELAY(0)
	)dut(
		.aclk(clk_if.clk_p),
		.aresetn(rst_if.reset_n),
		.aclken(1'b1),
		
		.fmbufcoln(FMBUFCOLN),
		.fmbufrown(FMBUFROWN),
		.grp_conv_buf_mode(GRP_CONV_BUF_MODE),
		.kbufgrpsz(KBUFGRPSZ),
		.sfc_n_each_wgtblk(SFC_N_EACH_WGTBLK),
		.kbufgrpn(KBUFGRPN),
		.fmbufbankn(FMBUFBANKN),
		
		.s_fm_rd_req_axis_data(s_fm_rd_req_axis_data),
		.s_fm_rd_req_axis_valid(s_fm_rd_req_axis_valid),
		.s_fm_rd_req_axis_ready(s_fm_rd_req_axis_ready),
		
		.s_kwgtblk_rd_req_axis_data(s_kwgtblk_rd_req_axis_data),
		.s_kwgtblk_rd_req_axis_valid(s_kwgtblk_rd_req_axis_valid),
		.s_kwgtblk_rd_req_axis_ready(s_kwgtblk_rd_req_axis_ready),
		
		.m_fm_fout_axis_data(m_fm_fout_axis_data),
		.m_fm_fout_axis_last(m_fm_fout_axis_last),
		.m_fm_fout_axis_valid(m_fm_fout_axis_valid),
		.m_fm_fout_axis_ready(m_fm_fout_axis_ready),
		
		.m_kout_wgtblk_axis_data(m_kout_wgtblk_axis_data),
		.m_kout_wgtblk_axis_last(m_kout_wgtblk_axis_last),
		.m_kout_wgtblk_axis_valid(m_kout_wgtblk_axis_valid),
		.m_kout_wgtblk_axis_ready(m_kout_wgtblk_axis_ready),
		
		.m0_dma_cmd_axis_data(m0_dma_cmd_axis_data),
		.m0_dma_cmd_axis_user(m0_dma_cmd_axis_user),
		.m0_dma_cmd_axis_last(m0_dma_cmd_axis_last),
		.m0_dma_cmd_axis_valid(m0_dma_cmd_axis_valid),
		.m0_dma_cmd_axis_ready(m0_dma_cmd_axis_ready),
		
		.s0_dma_strm_axis_data(s0_dma_strm_axis_data),
		.s0_dma_strm_axis_keep(s0_dma_strm_axis_keep),
		.s0_dma_strm_axis_last(s0_dma_strm_axis_last),
		.s0_dma_strm_axis_valid(s0_dma_strm_axis_valid),
		.s0_dma_strm_axis_ready(s0_dma_strm_axis_ready),
		
		.m1_dma_cmd_axis_data(m1_dma_cmd_axis_data),
		.m1_dma_cmd_axis_user(m1_dma_cmd_axis_user),
		.m1_dma_cmd_axis_last(m1_dma_cmd_axis_last),
		.m1_dma_cmd_axis_valid(m1_dma_cmd_axis_valid),
		.m1_dma_cmd_axis_ready(m1_dma_cmd_axis_ready),
		
		.s1_dma_strm_axis_data(s1_dma_strm_axis_data),
		.s1_dma_strm_axis_keep(s1_dma_strm_axis_keep),
		.s1_dma_strm_axis_last(s1_dma_strm_axis_last),
		.s1_dma_strm_axis_valid(s1_dma_strm_axis_valid),
		.s1_dma_strm_axis_ready(s1_dma_strm_axis_ready),
		
		.actual_rid_mp_tb_mem_clk(actual_rid_mp_tb_mem_clk),
		.actual_rid_mp_tb_mem_wen_a(actual_rid_mp_tb_mem_wen_a),
		.actual_rid_mp_tb_mem_addr_a(actual_rid_mp_tb_mem_addr_a),
		.actual_rid_mp_tb_mem_din_a(actual_rid_mp_tb_mem_din_a),
		.actual_rid_mp_tb_mem_ren_b(actual_rid_mp_tb_mem_ren_b),
		.actual_rid_mp_tb_mem_addr_b(actual_rid_mp_tb_mem_addr_b),
		.actual_rid_mp_tb_mem_dout_b(actual_rid_mp_tb_mem_dout_b),
		
		.buffer_rid_mp_tb_mem_clk(buffer_rid_mp_tb_mem_clk),
		.buffer_rid_mp_tb_mem_wen_a(buffer_rid_mp_tb_mem_wen_a),
		.buffer_rid_mp_tb_mem_addr_a(buffer_rid_mp_tb_mem_addr_a),
		.buffer_rid_mp_tb_mem_din_a(buffer_rid_mp_tb_mem_din_a),
		.buffer_rid_mp_tb_mem_ren_b(buffer_rid_mp_tb_mem_ren_b),
		.buffer_rid_mp_tb_mem_addr_b(buffer_rid_mp_tb_mem_addr_b),
		.buffer_rid_mp_tb_mem_dout_b(buffer_rid_mp_tb_mem_dout_b),
		
		.phy_conv_buf_mem_clk_a(phy_conv_buf_mem_clk_a),
		.phy_conv_buf_mem_en_a(phy_conv_buf_mem_en_a),
		.phy_conv_buf_mem_wen_a(phy_conv_buf_mem_wen_a),
		.phy_conv_buf_mem_addr_a(phy_conv_buf_mem_addr_a),
		.phy_conv_buf_mem_din_a(phy_conv_buf_mem_din_a),
		.phy_conv_buf_mem_dout_a(phy_conv_buf_mem_dout_a)
	);
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(LG_FMBUF_BUFFER_RID_WIDTH),
		.mem_depth(4096),
		.INIT_FILE("random"),
		.simulation_delay(0)
	)actual_rid_mp_tb_mem_u(
		.clk(actual_rid_mp_tb_mem_clk),
		
		.wen_a(actual_rid_mp_tb_mem_wen_a),
		.addr_a(actual_rid_mp_tb_mem_addr_a),
		.din_a(actual_rid_mp_tb_mem_din_a),
		
		.ren_b(actual_rid_mp_tb_mem_ren_b),
		.addr_b(actual_rid_mp_tb_mem_addr_b),
		.dout_b(actual_rid_mp_tb_mem_dout_b)
	);
	
	bram_simple_dual_port #(
		.style("LOW_LATENCY"),
		.mem_width(12),
		.mem_depth(2 ** LG_FMBUF_BUFFER_RID_WIDTH),
		.INIT_FILE("random"),
		.simulation_delay(0)
	)buffer_rid_mp_tb_mem_u(
		.clk(buffer_rid_mp_tb_mem_clk),
		
		.wen_a(buffer_rid_mp_tb_mem_wen_a),
		.addr_a(buffer_rid_mp_tb_mem_addr_a),
		.din_a(buffer_rid_mp_tb_mem_din_a),
		
		.ren_b(buffer_rid_mp_tb_mem_ren_b),
		.addr_b(buffer_rid_mp_tb_mem_addr_b),
		.dout_b(buffer_rid_mp_tb_mem_dout_b)
	);
	
	genvar phy_conv_buf_mem_i;
	generate
		for(phy_conv_buf_mem_i = 0;phy_conv_buf_mem_i < CBUF_BANK_N;phy_conv_buf_mem_i = phy_conv_buf_mem_i + 1)
		begin:phy_conv_buf_mem_blk
			bram_single_port #(
				.style("LOW_LATENCY"),
				.rw_mode("read_first"),
				.mem_width(ATOMIC_C*2*8),
				.mem_depth(CBUF_DEPTH_FOREACH_BANK),
				.INIT_FILE("no_init"),
				.byte_write_mode("true"),
				.simulation_delay(0)
			)phy_conv_buf_mem_u(
				.clk(phy_conv_buf_mem_clk_a),
				
				.en(phy_conv_buf_mem_en_a[phy_conv_buf_mem_i]),
				.wen(phy_conv_buf_mem_wen_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2-1:phy_conv_buf_mem_i*ATOMIC_C*2]),
				.addr(phy_conv_buf_mem_addr_a[phy_conv_buf_mem_i*16+clogb2(CBUF_DEPTH_FOREACH_BANK-1):phy_conv_buf_mem_i*16]),
				.din(phy_conv_buf_mem_din_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8]),
				.dout(phy_conv_buf_mem_dout_a[(phy_conv_buf_mem_i+1)*ATOMIC_C*2*8-1:phy_conv_buf_mem_i*ATOMIC_C*2*8])
			);
		end
	endgenerate
	
endmodule
