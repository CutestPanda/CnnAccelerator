`ifndef __PANDA_TEST_H
`define __PANDA_TEST_H

class DmaStrmAxisVsqr extends tue_sequencer_base #(
	.BASE(uvm_sequencer),
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(tue_configuration_dummy),
	.PROXY_STATUS(tue_status_dummy)
);
	
	panda_axis_master_sequencer dma_strm_axis_sqr;
	panda_axis_slave_sequencer dma_cmd_axis_sqr;
	
	`tue_component_default_constructor(DmaStrmAxisVsqr)
	`uvm_component_utils(DmaStrmAxisVsqr)
	
endclass

class DmaStrmAxisVseq #(
	string MEM_NAME = "fmap_mem"
)extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local int dma_strm_axis_byte_width;
	local PandaMemoryAdapter mem;
	
	local mailbox #(panda_axis_slave_trans) dma_cmd_mb;
	
	`uvm_declare_p_sequencer(DmaStrmAxisVsqr)
	
	function new(string name = "DmaStrmAxisVseq");
		super.new(name);
		
		this.set_automatic_phase_objection(0);
		
		this.dma_cmd_mb = new();
    endfunction
	
	task pre_body();
		super.pre_body();
		
		this.dma_strm_axis_byte_width = this.p_sequencer.dma_strm_axis_sqr.get_configuration().data_width / 8;
		
		if(!uvm_config_db #(PandaMemoryAdapter)::get(null, "", MEM_NAME, this.mem))
			`uvm_fatal(this.get_name(), $sformatf("cannot get %s!!!", MEM_NAME))
	endtask
	
	task body();
		panda_axis_trans dma_cmd_axis_req;
		panda_axis_slave_trans send_dma_cmd_axis_tr;
		panda_axis_slave_trans recv_dma_cmd_axis_tr;
		panda_axis_master_trans dma_strm_axis_tr;
		
		fork
			forever
			begin
				this.p_sequencer.dma_cmd_axis_sqr.get_request(dma_cmd_axis_req);
				
				`uvm_do_on_with(send_dma_cmd_axis_tr, this.p_sequencer.dma_cmd_axis_sqr, {})
				
				this.dma_cmd_mb.put(send_dma_cmd_axis_tr);
			end
			
			forever
			begin
				bit[23:0] btt;
				bit[31:0] baseaddr;
				
				this.dma_cmd_mb.get(recv_dma_cmd_axis_tr);
				
				{btt, baseaddr} = recv_dma_cmd_axis_tr.data[0][55:0];
				
				`uvm_create_on(dma_strm_axis_tr, this.p_sequencer.dma_strm_axis_sqr)
				
				dma_strm_axis_tr.len = (btt / this.dma_strm_axis_byte_width) + ((btt % this.dma_strm_axis_byte_width) ? 1:0);
				dma_strm_axis_tr.data = new[dma_strm_axis_tr.len];
				dma_strm_axis_tr.keep = new[dma_strm_axis_tr.len];
				
				for(int i = 0;i < dma_strm_axis_tr.len;i++)
				begin
					dma_strm_axis_tr.keep[i] = 
						((i == (dma_strm_axis_tr.len - 1)) && (btt % this.dma_strm_axis_byte_width)) ? 
							((1 << (btt % this.dma_strm_axis_byte_width)) - 1):
							((1 << this.dma_strm_axis_byte_width) - 1);
					
					for(int j = 0;j < this.dma_strm_axis_byte_width / 2;j++)
						dma_strm_axis_tr.data[i][16*j+:16] = this.mem.get(2, baseaddr, i * (this.dma_strm_axis_byte_width / 2) + j);
				end
				
				`uvm_send(dma_strm_axis_tr)
				
				/*
				`uvm_do_on_with(dma_strm_axis_tr, this.p_sequencer.dma_strm_axis_sqr, {
					len == ((btt / dma_strm_axis_byte_width) + ((btt % dma_strm_axis_byte_width) ? 1:0));
					
					foreach(data[i]){
						data[i] == mem.get(dma_strm_axis_byte_width, baseaddr, i);
					}
					
					foreach(keep[i]){
						if((i == (len - 1)) && (btt % dma_strm_axis_byte_width)){
							keep[i] == ((1 << (btt % dma_strm_axis_byte_width)) - 1);
						}else{
							keep[i] == ((1 << dma_strm_axis_byte_width) - 1);
						}
					}
				})
				*/
			end
		join
	endtask
	
	`uvm_object_param_utils(DmaStrmAxisVseq #(.MEM_NAME(MEM_NAME)))
	
endclass

class FmRdReqSeq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	rand bit to_rst_buf; // 是否重置缓存
	rand int unsigned actual_sfc_rid; // 实际表面行号
	rand int unsigned start_sfc_id; // 起始表面编号
	rand int unsigned sfc_n_to_rd; // 待读取的表面个数
	rand bit[31:0] sfc_row_baseaddr; // 表面行基地址
	rand int unsigned sfc_row_col_n_to_fetch; // 表面行列数
	rand int unsigned vld_data_n_foreach_sfc; // 每个表面的有效数据个数
	
	local int unsigned sfc_row_btt; // 表面行有效字节数
	
	constraint c_valid_sfc_row_baseaddr{
		sfc_row_baseaddr[0] == 1'b0;
	}
	
	function new(string name = "FmRdReqSeq");
		super.new(name);
		
		this.set_automatic_phase_objection(0);
    endfunction
	
	task body();
		panda_axis_master_trans tr;
		
		this.sfc_row_btt = this.sfc_row_col_n_to_fetch * this.vld_data_n_foreach_sfc * 2;
		
		`uvm_do_with(tr, {
			if(!to_rst_buf){
				data[0][4:0] == (vld_data_n_foreach_sfc - 1);
				data[0][28:5] == sfc_row_btt;
				data[0][60:29] == sfc_row_baseaddr;
				data[0][72:61] == (sfc_n_to_rd - 1);
				data[0][84:73] == start_sfc_id;
				data[0][96:85] == actual_sfc_rid;
			}
			data[0][97] == to_rst_buf;
			data[0][103:98] == 6'd0;
		})
    endtask
	
	`uvm_object_utils(FmRdReqSeq)
	
endclass

class KwgtblkRdReqSeq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	rand bit to_rst_buf; // 是否重置缓存
	rand int unsigned actual_cgrp_id_or_cgrpn; // 实际通道组号或卷积核核组实际通道组数
	rand int unsigned cgrp_id_ofs; // 通道组号偏移
	
	rand int unsigned wgtblk_id; // 权重块编号
	rand int unsigned start_sfc_id; // 起始表面编号
	rand int unsigned sfc_n_to_rd; // 待读取的表面个数
	rand int unsigned kernal_cgrp_baseaddr; // 卷积核通道组基地址
	rand int unsigned sfc_n_foreach_wgtblk; // 每个权重块的表面个数
	rand int unsigned vld_data_n_foreach_sfc; // 每个表面的有效数据个数
	
	rand kernal_sz_t kernal_shape; // 卷积核形状
	
	int unsigned kernal_cgrp_btt; // 卷积核通道组有效字节数
	
	function new(string name = "KwgtblkRdReqSeq");
		super.new(name);
		
		this.set_automatic_phase_objection(0);
    endfunction
	
	task body();
		panda_axis_master_trans tr;
		
		this.kernal_cgrp_btt = 
			ConvDataHubCfg::kernal_sz_t_to_int(this.kernal_shape) * this.sfc_n_foreach_wgtblk * this.vld_data_n_foreach_sfc * 2;
		
		`uvm_do_with(tr, {
			if(!to_rst_buf){
				data[0][4:0] == (vld_data_n_foreach_sfc - 1);
				data[0][11:5] == (sfc_n_foreach_wgtblk - 1);
				data[0][35:12] == kernal_cgrp_btt;
				data[0][67:36] == kernal_cgrp_baseaddr;
				data[0][72:68] == (sfc_n_to_rd - 1);
				data[0][79:73] == start_sfc_id;
				data[0][86:80] == wgtblk_id;
				data[0][96:87] == actual_cgrp_id_or_cgrpn;
			}else{
				data[0][86:77] == cgrp_id_ofs;
				data[0][96:87] == (actual_cgrp_id_or_cgrpn - 1);
			}
			
			data[0][97] == to_rst_buf;
			data[0][103:98] == 6'd0;
		})
    endtask
	
	`uvm_object_utils(KwgtblkRdReqSeq)
	
endclass

/**
特征图缓存测试用例#0:
	循环访问两个不同表面行(行#A, 行#B、行#A、行#B、...)
**/
class FmRdReqTestcase0Seq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local ConvDataHubCfg test_cfg;
	
	rand int unsigned item_id_to_access[2];
	
	function new(string name = "FmRdReqTestcase0Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
		
		if(this.test_cfg.total_fmrow_n < 2)
			`uvm_fatal(this.get_name(), "at least 2 rows for test!")
		
		if(!this.randomize() with {
			item_id_to_access[0] != item_id_to_access[1];
			
			item_id_to_access[0] < test_cfg.total_fmrow_n;
			item_id_to_access[1] < test_cfg.total_fmrow_n;
		})
			`uvm_fatal(this.get_name(), "cannot randomize!")
	endtask
	
	task body();
		FmRdReqSeq fm_rd_req_seq;
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
		
		for(int i = 0;i < 20;i++)
		begin
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b0;
				
				actual_sfc_rid == test_cfg.actual_sfc_rid_foreach_fmrow[item_id_to_access[i % 2]];
				
				start_sfc_id < sfc_row_col_n_to_fetch;
				(start_sfc_id + sfc_n_to_rd) <= sfc_row_col_n_to_fetch;
				sfc_n_to_rd[31] == 1'b0;
				sfc_n_to_rd > 0;
				
				sfc_row_col_n_to_fetch == test_cfg.fmrow_len;
				vld_data_n_foreach_sfc == test_cfg.sfc_data_n_foreach_fmrow[item_id_to_access[i % 2]];
				
				sfc_row_baseaddr == test_cfg.abs_baseaddr_foreach_fmrow[item_id_to_access[i % 2]];
			})
		end
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
	endtask
	
	`uvm_object_utils(FmRdReqTestcase0Seq)
	
endclass

/**
特征图缓存测试用例#1:
	重复访问相同表面行(行#A, 行#A、行#A、行#A、...)
**/
class FmRdReqTestcase1Seq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local ConvDataHubCfg test_cfg;
	
	rand int unsigned item_id_to_access;
	
	function new(string name = "FmRdReqTestcase1Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
		
		if(!this.randomize() with {
			item_id_to_access < test_cfg.total_fmrow_n;
		})
			`uvm_fatal(this.get_name(), "cannot randomize!")
	endtask
	
	task body();
		FmRdReqSeq fm_rd_req_seq;
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
		
		repeat(20)
		begin
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b0;
				
				actual_sfc_rid == test_cfg.actual_sfc_rid_foreach_fmrow[item_id_to_access];
				
				start_sfc_id < sfc_row_col_n_to_fetch;
				(start_sfc_id + sfc_n_to_rd) <= sfc_row_col_n_to_fetch;
				sfc_n_to_rd[31] == 1'b0;
				sfc_n_to_rd > 0;
				
				sfc_row_col_n_to_fetch == test_cfg.fmrow_len;
				vld_data_n_foreach_sfc == test_cfg.sfc_data_n_foreach_fmrow[item_id_to_access];
				
				sfc_row_baseaddr == test_cfg.abs_baseaddr_foreach_fmrow[item_id_to_access];
			})
		end
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
	endtask
	
	`uvm_object_utils(FmRdReqTestcase1Seq)
	
endclass

/**
特征图缓存测试用例#2:
	顺序遍历所有表面行(行#0, 行#1、行#2、行#3、...、行#(n-1))
**/
class FmRdReqTestcase2Seq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local ConvDataHubCfg test_cfg;
	
	function new(string name = "FmRdReqTestcase2Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
	endtask
	
	task body();
		FmRdReqSeq fm_rd_req_seq;
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
		
		repeat(4)
		begin
			for(int i = 0;i < test_cfg.total_fmrow_n;i++)
			begin
				`uvm_do_with(fm_rd_req_seq, {
					to_rst_buf == 1'b0;
					
					actual_sfc_rid == test_cfg.actual_sfc_rid_foreach_fmrow[i];
					
					start_sfc_id < sfc_row_col_n_to_fetch;
					(start_sfc_id + sfc_n_to_rd) <= sfc_row_col_n_to_fetch;
					sfc_n_to_rd[31] == 1'b0;
					sfc_n_to_rd > 0;
					
					sfc_row_col_n_to_fetch == test_cfg.fmrow_len;
					vld_data_n_foreach_sfc == test_cfg.sfc_data_n_foreach_fmrow[i];
					
					sfc_row_baseaddr == test_cfg.abs_baseaddr_foreach_fmrow[i];
				})
			end
		end
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
	endtask
	
	`uvm_object_utils(FmRdReqTestcase2Seq)
	
endclass

/**
特征图缓存测试用例#3:
	折返遍历所有表面行(行#0, 行#1、行#2、行#3、...、行#(n-1)、行#(n-2)、行#(n-3)、...、行#0)
**/
class FmRdReqTestcase3Seq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local ConvDataHubCfg test_cfg;
	
	function new(string name = "FmRdReqTestcase3Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
	endtask
	
	task body();
		FmRdReqSeq fm_rd_req_seq;
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
		
		for(int m = 0;m < 4;m++)
		begin
			for(int i = 0;i < test_cfg.total_fmrow_n;i++)
			begin
				`uvm_do_with(fm_rd_req_seq, {
					to_rst_buf == 1'b0;
					
					actual_sfc_rid == test_cfg.actual_sfc_rid_foreach_fmrow[(m % 2) ? (test_cfg.total_fmrow_n - 1 - i):i];
					
					start_sfc_id < sfc_row_col_n_to_fetch;
					(start_sfc_id + sfc_n_to_rd) <= sfc_row_col_n_to_fetch;
					sfc_n_to_rd[31] == 1'b0;
					sfc_n_to_rd > 0;
					
					sfc_row_col_n_to_fetch == test_cfg.fmrow_len;
					vld_data_n_foreach_sfc == test_cfg.sfc_data_n_foreach_fmrow[(m % 2) ? (test_cfg.total_fmrow_n - 1 - i):i];
					
					sfc_row_baseaddr == test_cfg.abs_baseaddr_foreach_fmrow[(m % 2) ? (test_cfg.total_fmrow_n - 1 - i):i];
				})
			end
		end
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
	endtask
	
	`uvm_object_utils(FmRdReqTestcase3Seq)
	
endclass

/**
特征图缓存测试用例#4:
	随机访问表面行
**/
class FmRdReqTestcase4Seq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local ConvDataHubCfg test_cfg;
	
	function new(string name = "FmRdReqTestcase4Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
	endtask
	
	task body();
		FmRdReqSeq fm_rd_req_seq;
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
		
		repeat(100)
		begin
			int unsigned item_id_to_access;
			
			item_id_to_access = $urandom_range(0, test_cfg.total_fmrow_n - 1);
			
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b0;
				
				actual_sfc_rid == test_cfg.actual_sfc_rid_foreach_fmrow[item_id_to_access];
				
				start_sfc_id < sfc_row_col_n_to_fetch;
				(start_sfc_id + sfc_n_to_rd) <= sfc_row_col_n_to_fetch;
				sfc_n_to_rd[31] == 1'b0;
				sfc_n_to_rd > 0;
				
				sfc_row_col_n_to_fetch == test_cfg.fmrow_len;
				vld_data_n_foreach_sfc == test_cfg.sfc_data_n_foreach_fmrow[item_id_to_access];
				
				sfc_row_baseaddr == test_cfg.abs_baseaddr_foreach_fmrow[item_id_to_access];
			})
		end
		
		if(starting_phase != null)
			`uvm_do_with(fm_rd_req_seq, {
				to_rst_buf == 1'b1;
			})
	endtask
	
	`uvm_object_utils(FmRdReqTestcase4Seq)
	
endclass

/** 特征图缓存所有测试用例 **/
class FmRdReqAllcaseSeq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "FmRdReqAllcaseSeq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		FmRdReqSeq fm_rd_req_seq;
		FmRdReqTestcase0Seq seq0;
		FmRdReqTestcase1Seq seq1;
		FmRdReqTestcase2Seq seq2;
		FmRdReqTestcase3Seq seq3;
		FmRdReqTestcase4Seq seq4;
		
		`uvm_create(seq0)
		`uvm_create(seq1)
		`uvm_create(seq2)
		`uvm_create(seq3)
		`uvm_create(seq4)
		
		if(!seq0.randomize())
			`uvm_fatal(this.get_name(), "seq0 failed to randomize!!!")
		if(!seq1.randomize())
			`uvm_fatal(this.get_name(), "seq1 failed to randomize!!!")
		if(!seq2.randomize())
			`uvm_fatal(this.get_name(), "seq2 failed to randomize!!!")
		if(!seq3.randomize())
			`uvm_fatal(this.get_name(), "seq3 failed to randomize!!!")
		if(!seq4.randomize())
			`uvm_fatal(this.get_name(), "seq4 failed to randomize!!!")
		
		`uvm_do_with(fm_rd_req_seq, {
			to_rst_buf == 1'b1;
		})
		
		seq0.start(this.get_sequencer(), this);
		seq1.start(this.get_sequencer(), this);
		seq2.start(this.get_sequencer(), this);
		seq3.start(this.get_sequencer(), this);
		seq4.start(this.get_sequencer(), this);
		
		`uvm_do_with(fm_rd_req_seq, {
			to_rst_buf == 1'b1;
		})
	endtask
	
	`uvm_object_utils(FmRdReqAllcaseSeq)
	
endclass

/**
卷积核缓存测试用例#0:
	循环访问某个核组的全部权重块
**/
class KernalRdReqTestcase0Seq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local ConvDataHubCfg test_cfg;
	
	function new(string name = "KernalRdReqTestcase0Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
	endtask
	
	task body();
		KwgtblkRdReqSeq kernal_rd_req_seq;
		
		if(starting_phase != null)
			`uvm_do_with(kernal_rd_req_seq, {
				to_rst_buf == 1'b1;
				actual_cgrp_id_or_cgrpn == test_cfg.cgrpn_foreach_kernal_set[0];
				cgrp_id_ofs == 0;
			})
		
		repeat(10)
		begin
			for(int unsigned c = 0;c < test_cfg.cgrpn_foreach_kernal_set[0];c++)
			begin
				for(int unsigned k = 0;k < ConvDataHubCfg::kernal_sz_t_to_int(test_cfg.kernal_shape);k++)
				begin
					`uvm_do_with(kernal_rd_req_seq, {
						to_rst_buf == 1'b0;
						actual_cgrp_id_or_cgrpn == c;
						wgtblk_id == k;
						start_sfc_id == 0;
						sfc_n_to_rd == test_cfg.wgtblk_w_foreach_kernal_set[0];
						kernal_cgrp_baseaddr == test_cfg.abs_baseaddr_foreach_cgrp[c];
						sfc_n_foreach_wgtblk == test_cfg.wgtblk_w_foreach_kernal_set[0];
						vld_data_n_foreach_sfc == test_cfg.depth_foreach_kernal_cgrp[c];
						
						kernal_shape == test_cfg.kernal_shape;
					})
				end
			end
		end
		
		if(starting_phase != null)
			`uvm_do_with(kernal_rd_req_seq, {
				to_rst_buf == 1'b1;
				actual_cgrp_id_or_cgrpn == test_cfg.cgrpn_foreach_kernal_set[0];
				cgrp_id_ofs == 0;
			})
	endtask
	
	`uvm_object_utils(KernalRdReqTestcase0Seq)
	
endclass

/**
卷积核缓存测试用例#1:
	遍历访问所有权重块
**/
class KernalRdReqTestcase1Seq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local ConvDataHubCfg test_cfg;
	
	function new(string name = "KernalRdReqTestcase1Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
	endtask
	
	task body();
		KwgtblkRdReqSeq kernal_rd_req_seq;
		int unsigned abs_cgrp_i;
		int unsigned now_cgrp_id_ofs;
		
		if(starting_phase != null)
			`uvm_do_with(kernal_rd_req_seq, {
				to_rst_buf == 1'b1;
				actual_cgrp_id_or_cgrpn == 1;
				cgrp_id_ofs == 0;
			})
		
		abs_cgrp_i = 0;
		now_cgrp_id_ofs = 0;
		
		for(int unsigned i = 0;i < test_cfg.total_kernal_set_n;i++)
		begin
			`uvm_do_with(kernal_rd_req_seq, {
				to_rst_buf == 1'b1;
				actual_cgrp_id_or_cgrpn == test_cfg.cgrpn_foreach_kernal_set[i];
				cgrp_id_ofs == now_cgrp_id_ofs;
			})
			
			for(int unsigned c = 0;c < test_cfg.cgrpn_foreach_kernal_set[i];c++)
			begin
				for(int unsigned k = 0;k < ConvDataHubCfg::kernal_sz_t_to_int(test_cfg.kernal_shape);k++)
				begin
					`uvm_do_with(kernal_rd_req_seq, {
						to_rst_buf == 1'b0;
						actual_cgrp_id_or_cgrpn == c;
						wgtblk_id == k;
						start_sfc_id == 0;
						sfc_n_to_rd == test_cfg.wgtblk_w_foreach_kernal_set[i];
						kernal_cgrp_baseaddr == test_cfg.abs_baseaddr_foreach_cgrp[abs_cgrp_i];
						sfc_n_foreach_wgtblk == test_cfg.wgtblk_w_foreach_kernal_set[i];
						vld_data_n_foreach_sfc == test_cfg.depth_foreach_kernal_cgrp[abs_cgrp_i];
						
						kernal_shape == test_cfg.kernal_shape;
					})
				end
				
				abs_cgrp_i++;
			end
			
			now_cgrp_id_ofs += test_cfg.cgrpn_foreach_kernal_set[i];
		end
		
		if(starting_phase != null)
			`uvm_do_with(kernal_rd_req_seq, {
				to_rst_buf == 1'b1;
				actual_cgrp_id_or_cgrpn == 1;
				cgrp_id_ofs == 0;
			})
	endtask
	
	`uvm_object_utils(KernalRdReqTestcase1Seq)
	
endclass

/**
卷积核缓存测试用例#2:
	遍历访问所有权重块, 核组内重复若干次
**/
class KernalRdReqTestcase2Seq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local ConvDataHubCfg test_cfg;
	
	function new(string name = "KernalRdReqTestcase2Seq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
	endtask
	
	task body();
		KwgtblkRdReqSeq kernal_rd_req_seq;
		int unsigned cgrp_i_base;
		int unsigned now_cgrp_id_ofs;
		
		if(starting_phase != null)
			`uvm_do_with(kernal_rd_req_seq, {
				to_rst_buf == 1'b1;
				actual_cgrp_id_or_cgrpn == 1;
				cgrp_id_ofs == 0;
			})
		
		cgrp_i_base = 0;
		now_cgrp_id_ofs = 0;
		
		for(int unsigned i = 0;i < test_cfg.total_kernal_set_n;i++)
		begin
			`uvm_do_with(kernal_rd_req_seq, {
				to_rst_buf == 1'b1;
				actual_cgrp_id_or_cgrpn == test_cfg.cgrpn_foreach_kernal_set[i];
				cgrp_id_ofs == now_cgrp_id_ofs;
			})
			
			repeat(5)
			begin
				for(int unsigned c = 0;c < test_cfg.cgrpn_foreach_kernal_set[i];c++)
				begin
					for(int unsigned k = 0;k < ConvDataHubCfg::kernal_sz_t_to_int(test_cfg.kernal_shape);k++)
					begin
						`uvm_do_with(kernal_rd_req_seq, {
							to_rst_buf == 1'b0;
							actual_cgrp_id_or_cgrpn == c;
							wgtblk_id == k;
							start_sfc_id == 0;
							sfc_n_to_rd == test_cfg.wgtblk_w_foreach_kernal_set[i];
							kernal_cgrp_baseaddr == test_cfg.abs_baseaddr_foreach_cgrp[cgrp_i_base + c];
							sfc_n_foreach_wgtblk == test_cfg.wgtblk_w_foreach_kernal_set[i];
							vld_data_n_foreach_sfc == test_cfg.depth_foreach_kernal_cgrp[cgrp_i_base + c];
							
							kernal_shape == test_cfg.kernal_shape;
						})
					end
				end
			end
			
			cgrp_i_base += test_cfg.cgrpn_foreach_kernal_set[i];
			now_cgrp_id_ofs += test_cfg.cgrpn_foreach_kernal_set[i];
		end
		
		if(starting_phase != null)
			`uvm_do_with(kernal_rd_req_seq, {
				to_rst_buf == 1'b1;
				actual_cgrp_id_or_cgrpn == 1;
				cgrp_id_ofs == 0;
			})
	endtask
	
	`uvm_object_utils(KernalRdReqTestcase2Seq)
	
endclass

class conv_data_hub_test extends panda_test_single_clk_base #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local int fmap_rd_req_tr_mcd;
	local int kernal_rd_req_tr_mcd;
	
	local DmaStrmAxisVsqr dma_axis_vsqr[2];
	
	local FmBufScoreboard fm_buf_scb;
	local KernalBufScoreboard kernal_buf_scb;
	
	local panda_axis_master_agent fm_rd_req_axis_mst_agt;
	local panda_axis_slave_agent fm_fout_axis_slv_agt;
	local panda_axis_master_agent kwgtblk_rd_req_axis_mst_agt;
	local panda_axis_slave_agent kout_wgtblk_axis_slv_agt;
	local panda_axis_master_agent dma_strm_axis_mst_agt[2];
	local panda_axis_slave_agent dma_cmd_axis_slv_agt[2];
	
	local panda_axis_configuration rd_req_axis_mst_cfg[2];
	local panda_axis_configuration dout_axis_slv_cfg[2];
	local panda_axis_configuration dma_strm_axis_mst_cfg[2];
	local panda_axis_configuration dma_cmd_axis_slv_cfg[2];
	
	local ConvDataHubCfg test_cfg;
	
	function new(string name = "conv_data_hub_test", uvm_component parent = null);
		super.new(name, parent);
		
		this.clk_period = 10ns;
		this.rst_duration = 1us;
		this.main_phase_drain_time = 10us;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.fmap_rd_req_tr_mcd = $fopen("fmap_rd_req_tr_log.txt");
		this.kernal_rd_req_tr_mcd = $fopen("kernal_rd_req_tr_log.txt");
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(ConvDataHubCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
		
		this.rd_req_axis_mst_cfg[0] = panda_axis_configuration::type_id::create("rd_req_axis_mst_cfg");
		if(!this.rd_req_axis_mst_cfg[0].randomize() with {
			data_width == 104;
			user_width == 0;
			
			valid_delay.min_delay == 0;
			valid_delay.mid_delay[0] == 4;
			valid_delay.mid_delay[1] == 20;
			valid_delay.max_delay == 30;
			valid_delay.weight_zero_delay == 5;
			valid_delay.weight_short_delay == 2;
			valid_delay.weight_long_delay == 1;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize rd_req_axis_mst_cfg!")
		
		if(!$cast(this.rd_req_axis_mst_cfg[1], this.rd_req_axis_mst_cfg[0].clone()))
			`uvm_fatal(get_name(), "cannot cast rd_req_axis_mst_cfg_clone!!!")
		
		this.dout_axis_slv_cfg[0] = panda_axis_configuration::type_id::create("dout_axis_slv_cfg");
		if(!this.dout_axis_slv_cfg[0].randomize() with {
			data_width == (test_cfg.atomic_c * 2 * 8);
			user_width == 0;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 1;
			ready_delay.mid_delay[1] == 1;
			ready_delay.max_delay == 3;
			ready_delay.weight_zero_delay == 3;
			ready_delay.weight_short_delay == 1;
			ready_delay.weight_long_delay == 1;
			
			default_ready == 1'b1;
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize dout_axis_slv_cfg!")
		
		if(!$cast(this.dout_axis_slv_cfg[1], this.dout_axis_slv_cfg[0].clone()))
			`uvm_fatal(get_name(), "cannot cast dout_axis_slv_cfg_clone!!!")
		
		this.dma_strm_axis_mst_cfg[0] = panda_axis_configuration::type_id::create("dma_strm_axis_mst_cfg");
		if(!this.dma_strm_axis_mst_cfg[0].randomize() with {
			data_width == test_cfg.stream_data_width;
			user_width == 0;
			
			valid_delay.min_delay == 0;
			valid_delay.mid_delay[0] == 1;
			valid_delay.mid_delay[1] == 1;
			valid_delay.max_delay == 2;
			valid_delay.weight_zero_delay == 3;
			valid_delay.weight_short_delay == 2;
			valid_delay.weight_long_delay == 1;
			
			has_keep == 1'b1;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize dma_strm_axis_mst_cfg!")
		
		if(!$cast(this.dma_strm_axis_mst_cfg[1], this.dma_strm_axis_mst_cfg[0].clone()))
			`uvm_fatal(get_name(), "cannot cast dma_strm_axis_mst_cfg_clone!!!")
		
		this.dma_cmd_axis_slv_cfg[0] = panda_axis_configuration::type_id::create("dma_cmd_axis_slv_cfg");
		if(!this.dma_cmd_axis_slv_cfg[0].randomize() with {
			data_width == 56;
			user_width == 1;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 30;
			ready_delay.mid_delay[1] == 50;
			ready_delay.max_delay == 60;
			ready_delay.weight_zero_delay == 1;
			ready_delay.weight_short_delay == 6;
			ready_delay.weight_long_delay == 3;
			
			default_ready == 1'b1;
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize dma_cmd_axis_slv_cfg!")
		
		if(!$cast(this.dma_cmd_axis_slv_cfg[1], this.dma_cmd_axis_slv_cfg[0].clone()))
			`uvm_fatal(get_name(), "cannot cast dma_cmd_axis_slv_cfg_clone!!!")
		
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "fm_rd_req_axis_vif_m", rd_req_axis_mst_cfg[0].vif))
			`uvm_fatal(get_name(), "virtual interface must be set for fm_rd_req_axis_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "kwgtblk_rd_req_axis_vif_m", rd_req_axis_mst_cfg[1].vif))
			`uvm_fatal(get_name(), "virtual interface must be set for kwgtblk_rd_req_axis_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "fm_fout_axis_vif_s", dout_axis_slv_cfg[0].vif))
			`uvm_fatal(get_name(), "virtual interface must be set for fm_fout_axis_vif_s!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "kout_wgtblk_axis_vif_s", dout_axis_slv_cfg[1].vif))
			`uvm_fatal(get_name(), "virtual interface must be set for kout_wgtblk_axis_vif_s!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "dma0_strm_axis_vif_m", dma_strm_axis_mst_cfg[0].vif))
			`uvm_fatal(get_name(), "virtual interface must be set for dma0_strm_axis_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "dma1_strm_axis_vif_m", dma_strm_axis_mst_cfg[1].vif))
			`uvm_fatal(get_name(), "virtual interface must be set for dma1_strm_axis_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "dma0_cmd_axis_vif_s", dma_cmd_axis_slv_cfg[0].vif))
			`uvm_fatal(get_name(), "virtual interface must be set for dma0_cmd_axis_vif_s!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "dma1_cmd_axis_vif_s", dma_cmd_axis_slv_cfg[1].vif))
			`uvm_fatal(get_name(), "virtual interface must be set for dma1_cmd_axis_vif_s!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.dma_axis_vsqr[0] = DmaStrmAxisVsqr::type_id::create("dma_axis_vsqr_0", this);
		this.dma_axis_vsqr[1] = DmaStrmAxisVsqr::type_id::create("dma_axis_vsqr_1", this);
		
		this.fm_buf_scb = FmBufScoreboard::type_id::create("fm_buf_scb", this);
		this.kernal_buf_scb = KernalBufScoreboard::type_id::create("kernal_buf_scb", this);
		
		this.fm_rd_req_axis_mst_agt = panda_axis_master_agent::type_id::create("fm_rd_req_axis_mst_agt", this);
		this.fm_rd_req_axis_mst_agt.active_agent();
		this.fm_rd_req_axis_mst_agt.set_configuration(this.rd_req_axis_mst_cfg[0]);
		
		this.fm_fout_axis_slv_agt = panda_axis_slave_agent::type_id::create("fm_fout_axis_slv_agt", this);
		this.fm_fout_axis_slv_agt.active_agent();
		this.fm_fout_axis_slv_agt.set_configuration(this.dout_axis_slv_cfg[0]);
		
		this.kwgtblk_rd_req_axis_mst_agt = panda_axis_master_agent::type_id::create("kwgtblk_rd_req_axis_mst_agt", this);
		this.kwgtblk_rd_req_axis_mst_agt.active_agent();
		this.kwgtblk_rd_req_axis_mst_agt.set_configuration(this.rd_req_axis_mst_cfg[1]);
		
		this.kout_wgtblk_axis_slv_agt = panda_axis_slave_agent::type_id::create("kout_wgtblk_axis_slv_agt", this);
		this.kout_wgtblk_axis_slv_agt.active_agent();
		this.kout_wgtblk_axis_slv_agt.set_configuration(this.dout_axis_slv_cfg[1]);
		
		this.dma_strm_axis_mst_agt[0] = panda_axis_master_agent::type_id::create("dma_strm_axis_mst_agt_0", this);
		this.dma_strm_axis_mst_agt[0].active_agent();
		this.dma_strm_axis_mst_agt[0].set_configuration(this.dma_strm_axis_mst_cfg[0]);
		
		this.dma_cmd_axis_slv_agt[0] = panda_axis_slave_agent::type_id::create("dma_cmd_axis_slv_agt_0", this);
		this.dma_cmd_axis_slv_agt[0].active_agent();
		this.dma_cmd_axis_slv_agt[0].set_configuration(this.dma_cmd_axis_slv_cfg[0]);
		
		this.dma_strm_axis_mst_agt[1] = panda_axis_master_agent::type_id::create("dma_strm_axis_mst_agt_1", this);
		this.dma_strm_axis_mst_agt[1].active_agent();
		this.dma_strm_axis_mst_agt[1].set_configuration(this.dma_strm_axis_mst_cfg[1]);
		
		this.dma_cmd_axis_slv_agt[1] = panda_axis_slave_agent::type_id::create("dma_cmd_axis_slv_agt_1", this);
		this.dma_cmd_axis_slv_agt[1].active_agent();
		this.dma_cmd_axis_slv_agt[1].set_configuration(this.dma_cmd_axis_slv_cfg[1]);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.dma_axis_vsqr[0].dma_strm_axis_sqr = this.dma_strm_axis_mst_agt[0].sequencer;
		this.dma_axis_vsqr[0].dma_cmd_axis_sqr = this.dma_cmd_axis_slv_agt[0].sequencer;
		this.dma_axis_vsqr[1].dma_strm_axis_sqr = this.dma_strm_axis_mst_agt[1].sequencer;
		this.dma_axis_vsqr[1].dma_cmd_axis_sqr = this.dma_cmd_axis_slv_agt[1].sequencer;
		
		this.dma_axis_vsqr[0].set_default_sequence("main_phase", DmaStrmAxisVseq #(.MEM_NAME("fmap_mem"))::type_id::get());
		this.dma_axis_vsqr[1].set_default_sequence("main_phase", DmaStrmAxisVseq #(.MEM_NAME("kernal_mem"))::type_id::get());
		this.fm_rd_req_axis_mst_agt.sequencer.set_default_sequence("main_phase", FmRdReqAllcaseSeq::type_id::get());
		this.fm_fout_axis_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
		this.kwgtblk_rd_req_axis_mst_agt.sequencer.set_default_sequence("main_phase", KernalRdReqTestcase2Seq::type_id::get());
		this.kout_wgtblk_axis_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
		
		this.fm_rd_req_axis_mst_agt.item_port.connect(this.fm_buf_scb.rd_req_port);
		this.fm_fout_axis_slv_agt.item_port.connect(this.fm_buf_scb.fout_port);
		
		this.kwgtblk_rd_req_axis_mst_agt.item_port.connect(this.kernal_buf_scb.rd_req_port);
		this.kout_wgtblk_axis_slv_agt.item_port.connect(this.kernal_buf_scb.fout_port);
		
		this.fm_buf_scb.set_rd_req_tr_mcd(this.fmap_rd_req_tr_mcd);
		this.kernal_buf_scb.set_rd_req_tr_mcd(this.kernal_rd_req_tr_mcd);
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		$fclose(this.fmap_rd_req_tr_mcd);
		$fclose(this.kernal_rd_req_tr_mcd);
	endfunction
	
	`uvm_component_utils(conv_data_hub_test)
	
endclass

`endif
