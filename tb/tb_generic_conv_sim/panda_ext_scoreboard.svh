`ifndef __PANDA_EXT_SCOREBOARD_H

`define __PANDA_EXT_SCOREBOARD_H

`uvm_analysis_imp_decl(_blk_ctrl)
`uvm_analysis_imp_decl(_rd_req)
`uvm_analysis_imp_decl(_fout)
`uvm_analysis_imp_decl(_final_res)
`uvm_analysis_imp_decl(_acmlt_in)

virtual class FmapOutPtCalProcListener extends uvm_object;
	
	virtual function void on_upd_out_pt_type0(
		uvm_object tr,
		int unsigned kset_id, int unsigned oy, int unsigned ox,
		int unsigned ky, int unsigned kx, int unsigned cgrp_id,
		int unsigned cal_rid
	);
		// blank
	endfunction
	
	virtual function void on_upd_out_pt_type1(
		uvm_object tr,
		int unsigned kset_id, int unsigned oy, int unsigned ox,
		int unsigned ky, int unsigned kx, int unsigned cgrp_id,
		int unsigned sfc_id
	);
		// blank
	endfunction
	
	`tue_object_default_constructor(FmapOutPtCalProcListener)
	
endclass

class FmapAccessReqGenScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	uvm_analysis_imp_blk_ctrl #(panda_blk_ctrl_abstract_trans, FmapAccessReqGenScoreboard) blk_ctrl_port;
	uvm_analysis_imp_rd_req #(panda_axis_trans, FmapAccessReqGenScoreboard) rd_req_port;
	
	local panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans blk_ctrl_fifo[$];
	local FmRdReqTransAdapter rd_req_fifo[$];
	
	int atomic_c = 4; // 通道并行数
	
	local int unsigned blk_ctrl_tr_id;
	local int blk_ctrl_tr_mcd = UVM_STDOUT;
	local int unsigned rd_req_tr_id;
	local int rd_req_tr_mcd = UVM_STDOUT;
	
	local int unsigned match_tr_n;
	local int unsigned mismatch_tr_n;
	local int unsigned rst_tr_n;
	local int unsigned rid_create_n;
	local int unsigned rid_reuse_n;
	local int unsigned rid_mismatch_n;
	
	function void set_blk_ctrl_tr_mcd(int mcd);
		this.blk_ctrl_tr_mcd = mcd;
	endfunction
	
	function void set_rd_req_tr_mcd(int mcd);
		this.rd_req_tr_mcd = mcd;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.blk_ctrl_port = new("blk_ctrl_port", this);
		this.rd_req_port = new("rd_req_port", this);
		
		this.blk_ctrl_tr_id = 0;
		this.rd_req_tr_id = 0;
		
		this.match_tr_n = 0;
		this.mismatch_tr_n = 0;
		this.rst_tr_n = 0;
		
		this.rid_create_n = 0;
		this.rid_reuse_n = 0;
		this.rid_mismatch_n = 0;
	endfunction
	
	virtual function void write_blk_ctrl(panda_blk_ctrl_abstract_trans tr);
		panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans blk_ctrl_tr;
		
		if(!$cast(blk_ctrl_tr, tr))
			`uvm_fatal(this.get_name(), "cannot cast panda_blk_ctrl_abstract_trans to panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans!")
		
		blk_ctrl_tr.id = this.blk_ctrl_tr_id;
		`panda_print_with(blk_ctrl_tr, this.blk_ctrl_tr_mcd, Util::get_object_printer())
		
		this.blk_ctrl_fifo.push_back(blk_ctrl_tr);
		
		this.blk_ctrl_tr_id++;
	endfunction
	
	virtual function void write_rd_req(panda_axis_trans tr);
		FmRdReqTransAdapter rd_req_adapter;
		
		rd_req_adapter = FmRdReqTransAdapter::type_id::create();
		rd_req_adapter.convert(tr);
		rd_req_adapter.id = this.rd_req_tr_id;
		
		`panda_print_with(rd_req_adapter, this.rd_req_tr_mcd, Util::get_object_printer())
		
		this.rd_req_fifo.push_back(rd_req_adapter);
		
		this.rd_req_tr_id++;
	endfunction
	
	task main_phase(uvm_phase phase);
		forever
		begin
			panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans blk_ctrl_tr;
			
			wait(this.blk_ctrl_fifo.size() > 0);
			
			blk_ctrl_tr = this.blk_ctrl_fifo.pop_front();
			
			check_rd_req_runtime(blk_ctrl_tr);
		end
	endtask
	
	task check_rd_req_runtime(panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans blk_ctrl_tr);
		int chn_n_in_kernal_set;
		int cgrp_n;
		int sfc_depth_of_last_cgrp;
		int bytes_n_foreach_data;
		
		int rid_to_cgrp_id_hash_tb[int];
		int rid_to_phy_y_hash_tb[int];
		
		chn_n_in_kernal_set = blk_ctrl_tr.is_grp_conv_mode ? blk_ctrl_tr.n_foreach_group:blk_ctrl_tr.fmap_chn_n;
		cgrp_n = (chn_n_in_kernal_set / this.atomic_c) + ((chn_n_in_kernal_set % this.atomic_c) ? 1:0);
		sfc_depth_of_last_cgrp = (chn_n_in_kernal_set % this.atomic_c) ? (chn_n_in_kernal_set % this.atomic_c):this.atomic_c;
		bytes_n_foreach_data = blk_ctrl_tr.is_16bit_data ? 2:1;
		
		for(int s = 0;s < blk_ctrl_tr.kernal_set_n;s++)
		begin
			int logic_y_base;
			
			logic_y_base = 0;
			
			for(int y = 0;y < blk_ctrl_tr.ofmap_h;y++)
			begin
				for(int c = 0;c < cgrp_n;c++)
				begin
					int logic_y_ofs;
					
					logic_y_ofs = 0;
					
					for(int k = 0;k < blk_ctrl_tr.kernal_h;k++)
					begin
						int phy_y;
						bit row_masked;
						
						this.convert_logic_y(blk_ctrl_tr, logic_y_base + logic_y_ofs, phy_y, row_masked);
						
						if(!row_masked)
						begin
							FmRdReqTransAdapter exp_tr;
							
							exp_tr = FmRdReqTransAdapter::type_id::create();
							
							exp_tr.to_rst_buf = 1'b0;
							exp_tr.start_sfc_id = 0;
							exp_tr.sfc_n_to_rd = blk_ctrl_tr.ifmap_w;
							exp_tr.vld_data_n_foreach_sfc = (c == (cgrp_n - 1)) ? sfc_depth_of_last_cgrp:this.atomic_c;
							exp_tr.sfc_row_btt = blk_ctrl_tr.ifmap_w * exp_tr.vld_data_n_foreach_sfc * bytes_n_foreach_data;
							exp_tr.sfc_row_baseaddr = 
								blk_ctrl_tr.fmap_baseaddr + 
								(blk_ctrl_tr.is_grp_conv_mode ? (s * blk_ctrl_tr.data_size_foreach_group):0) + 
								(c * blk_ctrl_tr.ifmap_size * this.atomic_c * bytes_n_foreach_data) + 
								(phy_y * blk_ctrl_tr.ifmap_w * exp_tr.vld_data_n_foreach_sfc * bytes_n_foreach_data);
							
							for(int p = 0;p < blk_ctrl_tr.kernal_w;p++)
							begin
								while(1)
								begin
									FmRdReqTransAdapter res_tr;
									
									wait(this.rd_req_fifo.size() > 0);
									
									res_tr = this.rd_req_fifo.pop_front();
									
									if(!res_tr.to_rst_buf)
									begin
										bit actual_sfc_rid_check_passed;
										
										actual_sfc_rid_check_passed = 1'b1;
										
										exp_tr.actual_sfc_rid = res_tr.actual_sfc_rid;
										
										if(rid_to_cgrp_id_hash_tb.exists(res_tr.actual_sfc_rid))
										begin
											int mapping_cgrpid;
											int mapping_phy_y;
											
											mapping_cgrpid = rid_to_cgrp_id_hash_tb[res_tr.actual_sfc_rid];
											mapping_phy_y = rid_to_phy_y_hash_tb[res_tr.actual_sfc_rid];
											
											if(mapping_cgrpid == c && mapping_phy_y == phy_y)
											begin
												`uvm_info(this.get_name(), $sformatf("reuse: %0x -> cgrpid = %0d, phy_y = %0d", res_tr.actual_sfc_rid, c, phy_y), UVM_LOW)
												
												this.rid_reuse_n++;
											end
											else
											begin
												`uvm_error(this.get_name(), "actual_sfc_rid mismatch")
												
												actual_sfc_rid_check_passed = 1'b0;
												
												this.rid_mismatch_n++;
											end
										end
										else
										begin
											`uvm_info(this.get_name(), $sformatf("create: %0x -> cgrpid = %0d, phy_y = %0d", res_tr.actual_sfc_rid, c, phy_y), UVM_LOW)
											
											rid_to_cgrp_id_hash_tb[res_tr.actual_sfc_rid] = c;
											rid_to_phy_y_hash_tb[res_tr.actual_sfc_rid] = phy_y;
											
											this.rid_create_n++;
										end
										
										if(res_tr.compare(exp_tr) && actual_sfc_rid_check_passed)
										begin
											`uvm_info(this.get_name(), $sformatf("check successfully(id = %0d)", res_tr.id), UVM_LOW)
											
											this.match_tr_n++;
										end
										else
										begin
											`uvm_error(this.get_name(), $sformatf("failed to check(id = %0d)", res_tr.id))
											
											this.mismatch_tr_n++;
										end
										
										break;
									end
									else
									begin
										`uvm_info(this.get_name(), $sformatf("get a rst tr(id = %0d)", res_tr.id), UVM_LOW)
										
										rid_to_cgrp_id_hash_tb.delete();
										rid_to_phy_y_hash_tb.delete();
										
										this.rst_tr_n++;
									end
								end
							end
						end
						
						logic_y_ofs += (blk_ctrl_tr.kernal_dilation_vtc_n + 1);
					end
				end
				
				logic_y_base += blk_ctrl_tr.conv_vertical_stride;
			end
		end
		
		`uvm_info(this.get_name(), "finish checking blk_ctrl_tr", UVM_LOW)
	endtask
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info(this.get_name(), $sformatf("match_tr_n = %0d", this.match_tr_n), UVM_LOW)
		`uvm_info(this.get_name(), $sformatf("mismatch_tr_n = %0d", this.mismatch_tr_n), UVM_LOW)
		`uvm_info(this.get_name(), $sformatf("rst_tr_n = %0d", this.rst_tr_n), UVM_LOW)
		
		`uvm_info(this.get_name(), $sformatf("rid_create_n = %0d", this.rid_create_n), UVM_LOW)
		`uvm_info(this.get_name(), $sformatf("rid_reuse_n = %0d", this.rid_reuse_n), UVM_LOW)
		`uvm_info(this.get_name(), $sformatf("rid_mismatch_n = %0d", this.rid_mismatch_n), UVM_LOW)
	endfunction
	
	local function void convert_logic_y(panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans blk_ctrl_tr, int logic_y,
		output int phy_y, output bit row_masked);
		if(
			((logic_y >= blk_ctrl_tr.external_padding_top) && (logic_y <= blk_ctrl_tr.ext_i_bottom)) && 
			(((logic_y - blk_ctrl_tr.external_padding_top) % (blk_ctrl_tr.inner_padding_top_bottom + 1)) == 0)
		)
		begin
			phy_y = (logic_y - blk_ctrl_tr.external_padding_top) / (blk_ctrl_tr.inner_padding_top_bottom + 1);
			row_masked = 1'b0;
		end
		else
		begin
			phy_y = 0;
			row_masked = 1'b1;
		end
	endfunction
	
	`tue_component_default_constructor(FmapAccessReqGenScoreboard)
	`uvm_component_utils(FmapAccessReqGenScoreboard)
	
endclass

class KernalAccessReqGenScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	uvm_analysis_imp_blk_ctrl #(panda_blk_ctrl_abstract_trans, KernalAccessReqGenScoreboard) blk_ctrl_port;
	uvm_analysis_imp_rd_req #(panda_axis_trans, KernalAccessReqGenScoreboard) kwgtblk_rd_req_port;
	
	int atomic_c = 4; // 通道并行数
	int atomic_k = 8; // 核并行数
	
	local int unsigned blk_ctrl_tr_id;
	local int blk_ctrl_tr_mcd = UVM_STDOUT;
	local int unsigned rd_req_tr_id;
	local int rd_req_tr_mcd = UVM_STDOUT;
	
	local panda_kernal_access_req_gen_blk_ctrl_trans blk_ctrl_tr_fifo[$];
	local KernalRdReqTransAdapter kwgtblk_rd_req_tr_fifo[$];
	
	function void set_blk_ctrl_tr_mcd(int mcd);
		this.blk_ctrl_tr_mcd = mcd;
	endfunction
	
	function void set_rd_req_tr_mcd(int mcd);
		this.rd_req_tr_mcd = mcd;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.blk_ctrl_port = new("blk_ctrl_port", this);
		this.kwgtblk_rd_req_port = new("kwgtblk_rd_req_port", this);
		
		this.blk_ctrl_tr_id = 0;
		this.rd_req_tr_id = 0;
	endfunction
	
	virtual function void write_blk_ctrl(panda_blk_ctrl_abstract_trans tr);
		panda_kernal_access_req_gen_blk_ctrl_trans blk_ctrl_tr;
		
		if(!$cast(blk_ctrl_tr, tr))
			`uvm_fatal(this.get_name(), "cannot cast panda_blk_ctrl_abstract_trans to panda_kernal_access_req_gen_blk_ctrl_trans!")
		
		blk_ctrl_tr.id = this.blk_ctrl_tr_id;
		`panda_print_with(blk_ctrl_tr, this.blk_ctrl_tr_mcd, Util::get_object_printer())
		
		this.blk_ctrl_tr_fifo.push_back(blk_ctrl_tr);
		
		this.blk_ctrl_tr_id++;
	endfunction
	
	virtual function void write_rd_req(panda_axis_trans tr);
		KernalRdReqTransAdapter rd_req_adapter;
		
		rd_req_adapter = KernalRdReqTransAdapter::type_id::create();
		rd_req_adapter.convert(tr);
		rd_req_adapter.id = this.rd_req_tr_id;
		
		`panda_print_with(rd_req_adapter, this.rd_req_tr_mcd, Util::get_object_printer())
		
		this.kwgtblk_rd_req_tr_fifo.push_back(rd_req_adapter);
		
		this.rd_req_tr_id++;
	endfunction
	
	task main_phase(uvm_phase phase);
		int blk_ctrl_tr_i;
		
		blk_ctrl_tr_i = 0;
		
		forever
		begin
			panda_kernal_access_req_gen_blk_ctrl_trans blk_ctrl_tr;
			
			wait(this.blk_ctrl_tr_fifo.size() > 0);
			
			blk_ctrl_tr = this.blk_ctrl_tr_fifo.pop_front();
			
			this.check_runtime(blk_ctrl_tr, blk_ctrl_tr_i);
			
			blk_ctrl_tr_i++;
		end
	endtask
	
	local task check_runtime(panda_kernal_access_req_gen_blk_ctrl_trans blk_ctrl_tr, int blk_ctrl_tr_i);
		KernalRdReqTransAdapter exp_rd_req_tr;
		KernalRdReqTransAdapter res_rd_req_tr;
		
		int kernal_set_n; // 核组总数
		int cgrpn; // 通道组总数
		int kernal_set_ofs_addr; // 核组偏移地址
		
		if(blk_ctrl_tr.is_grp_conv_mode)
			kernal_set_n = blk_ctrl_tr.group_n;
		else
			kernal_set_n = 
				(blk_ctrl_tr.kernal_num_n / this.atomic_k) + 
				((blk_ctrl_tr.kernal_num_n % this.atomic_k) ? 1:0);
		
		cgrpn = blk_ctrl_tr.cgrpn_foreach_kernal_set;
		kernal_set_ofs_addr = 0;
		
		for(int k = 0;k < kernal_set_n;k++)
		begin
			int kwgtblk_w; // 权重块宽度
			int logic_y_base;
			
			if(blk_ctrl_tr.is_grp_conv_mode)
				kwgtblk_w = blk_ctrl_tr.n_foreach_group;
			else
			begin
				if(k == (kernal_set_n - 1))
					kwgtblk_w = 
						(blk_ctrl_tr.kernal_num_n % this.atomic_k) ? 
							(blk_ctrl_tr.kernal_num_n % this.atomic_k):
							this.atomic_k;
				else
					kwgtblk_w = this.atomic_k;
			end
			
			logic_y_base = 0;
			
			exp_rd_req_tr = KernalRdReqTransAdapter::type_id::create();
			
			exp_rd_req_tr.to_rst_buf = 1'b1;
			exp_rd_req_tr.actual_cgrp_id_or_cgrpn = cgrpn;
			exp_rd_req_tr.cgrp_id_ofs = k * cgrpn;
			
			wait(this.kwgtblk_rd_req_tr_fifo.size() > 0);
			
			res_rd_req_tr = this.kwgtblk_rd_req_tr_fifo.pop_front();
			
			if(exp_rd_req_tr.compare(res_rd_req_tr))
				`uvm_info(this.get_name(), $sformatf("rst_check tr%0d kset%0d Match", blk_ctrl_tr_i, k), UVM_LOW)
			else
				`uvm_error(this.get_name(), $sformatf("rst_check tr%0d kset%0d Mismatch", blk_ctrl_tr_i, k))
			
			for(int h = 0;h < blk_ctrl_tr.ofmap_h;h++)
			begin
				int cgrp_ofs_addr; // 通道组偏移地址
				
				cgrp_ofs_addr = 0;
				
				for(int c = 0;c < cgrpn;c++)
				begin
					int sfc_depth; // 表面深度
					int wgtblk_id; // 权重块ID
					int logic_y_ofs;
					
					if(c == (cgrpn - 1))
						sfc_depth = 
							(blk_ctrl_tr.kernal_chn_n % this.atomic_c) ? 
								(blk_ctrl_tr.kernal_chn_n % this.atomic_c):
								this.atomic_c;
					else
						sfc_depth = this.atomic_c;
					
					wgtblk_id = 0;
					logic_y_ofs = 0;
					
					for(int y = 0;y < Util::kernal_sz_t_to_w_h(blk_ctrl_tr.kernal_shape);y++)
					begin
						for(int x = 0;x < Util::kernal_sz_t_to_w_h(blk_ctrl_tr.kernal_shape);x++)
						begin
							if(!this.get_row_mask(blk_ctrl_tr, logic_y_base + logic_y_ofs))
							begin
								exp_rd_req_tr = KernalRdReqTransAdapter::type_id::create();
								
								exp_rd_req_tr.to_rst_buf = 1'b0;
								exp_rd_req_tr.actual_cgrp_id_or_cgrpn = c;
								exp_rd_req_tr.wgtblk_id = wgtblk_id;
								exp_rd_req_tr.start_sfc_id = 0;
								exp_rd_req_tr.sfc_n_to_rd = kwgtblk_w;
								exp_rd_req_tr.kernal_cgrp_baseaddr = 
									blk_ctrl_tr.kernal_wgt_baseaddr + kernal_set_ofs_addr + cgrp_ofs_addr;
								exp_rd_req_tr.kernal_cgrp_btt = 
									Util::kernal_sz_t_to_int(blk_ctrl_tr.kernal_shape) * 
									kwgtblk_w * sfc_depth * (blk_ctrl_tr.is_16bit_wgt ? 2:1);
								exp_rd_req_tr.sfc_n_foreach_wgtblk = kwgtblk_w;
								exp_rd_req_tr.vld_data_n_foreach_sfc = sfc_depth;
								
								wait(this.kwgtblk_rd_req_tr_fifo.size() > 0);
								
								res_rd_req_tr = this.kwgtblk_rd_req_tr_fifo.pop_front();
								
								if(exp_rd_req_tr.compare(res_rd_req_tr))
									`uvm_info(this.get_name(), $sformatf("normal_check tr%0d kset%0d ofmap_h%0d cgrp%0d blk%0d Match", blk_ctrl_tr_i, k, h, c, wgtblk_id), UVM_LOW)
								else
									`uvm_error(this.get_name(), $sformatf("normal_check tr%0d kset%0d ofmap_h%0d cgrp%0d blk%0d Mismatch", blk_ctrl_tr_i, k, h, c, wgtblk_id))
							end
							
							wgtblk_id++;
						end
						
						logic_y_ofs += (blk_ctrl_tr.kernal_dilation_vtc_n + 1);
					end
					
					cgrp_ofs_addr += 
						Util::kernal_sz_t_to_int(blk_ctrl_tr.kernal_shape) * 
						kwgtblk_w * sfc_depth * (blk_ctrl_tr.is_16bit_wgt ? 2:1);
				end
				
				logic_y_base += blk_ctrl_tr.conv_vertical_stride;
			end
			
			kernal_set_ofs_addr += 
				Util::kernal_sz_t_to_int(blk_ctrl_tr.kernal_shape) * 
				kwgtblk_w * 
				(blk_ctrl_tr.is_grp_conv_mode ? blk_ctrl_tr.n_foreach_group:blk_ctrl_tr.kernal_chn_n) * 
				(blk_ctrl_tr.is_16bit_wgt ? 2:1);
		end
		
		wait(this.kwgtblk_rd_req_tr_fifo.size() > 0);
		
		res_rd_req_tr = this.kwgtblk_rd_req_tr_fifo.pop_front();
		
		if(res_rd_req_tr.to_rst_buf)
			`uvm_info(this.get_name(), $sformatf("rst_check tr%0d Match", blk_ctrl_tr_i), UVM_LOW)
		else
			`uvm_error(this.get_name(), $sformatf("rst_check tr%0d Mismatch", blk_ctrl_tr_i))
		
		`uvm_info(this.get_name(), $sformatf("pkt%0d completed", blk_ctrl_tr_i), UVM_LOW)
	endtask
	
	local function bit get_row_mask(panda_kernal_access_req_gen_blk_ctrl_trans blk_ctrl_tr, int logic_y);
		if(
			((logic_y >= blk_ctrl_tr.external_padding_top) && (logic_y <= blk_ctrl_tr.ext_i_bottom)) && 
			(((logic_y - blk_ctrl_tr.external_padding_top) % (blk_ctrl_tr.inner_padding_top_bottom + 1)) == 0)
		)
		begin
			return 1'b0;
		end
		else
		begin
			return 1'b1;
		end
	endfunction
	
	`tue_component_default_constructor(KernalAccessReqGenScoreboard)
	`uvm_component_utils(KernalAccessReqGenScoreboard)
	
endclass

class ConvDataHubScoreboardBase #(
	string MEM_NAME = "fmap_mem",
	type RdReqTransAdapterType = FmRdReqTransAdapter
)extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	typedef ConvDataHubScoreboardBase #(.MEM_NAME(MEM_NAME), .RdReqTransAdapterType(RdReqTransAdapterType)) this_type;
	
	uvm_analysis_imp_rd_req #(panda_axis_trans, this_type) rd_req_port;
	uvm_analysis_imp_fout #(panda_axis_trans, this_type) fout_port;
	
	protected RdReqTransAdapterType rd_req_tr_fifo[$];
	protected panda_axis_trans fout_tr_fifo[$];
	
	protected PandaMemoryAdapter mem;
	
	protected int unsigned chk_id;
	protected int unsigned success_cnt;
	protected int unsigned failure_cnt;
	
	protected int rd_req_tr_mcd = UVM_STDOUT;
	protected int unsigned rd_req_tr_id;
	
	function void set_rd_req_tr_mcd(int mcd);
		this.rd_req_tr_mcd = mcd;
	endfunction
	
	virtual function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.rd_req_port = new("rd_req_port", this);
		this.fout_port = new("fout_port", this);
		
		this.chk_id = 0;
		this.success_cnt = 0;
		this.failure_cnt = 0;
		
		this.rd_req_tr_id = 0;
		
		if(!uvm_config_db #(PandaMemoryAdapter)::get(null, "", MEM_NAME, this.mem))
			`uvm_fatal(this.get_name(), $sformatf("cannot get %0s!!!", MEM_NAME))
	endfunction
	
	virtual function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info(this.get_name(), $sformatf("get %0d trans, success = %0d, failure = %0d", this.chk_id, this.success_cnt, this.failure_cnt), UVM_LOW)
	endfunction
	
	virtual function void write_rd_req(panda_axis_trans tr);
		RdReqTransAdapterType rd_req_tr;
		
		rd_req_tr = RdReqTransAdapterType::type_id::create();
		rd_req_tr.convert(tr);
		
		rd_req_tr.id = this.rd_req_tr_id;
		`panda_print_with(rd_req_tr, this.rd_req_tr_mcd, Util::get_object_printer())
		
		if(rd_req_tr.to_rst_buf)
			`uvm_info(this.get_name(), "get rst_buf", UVM_LOW)
		else
			this.rd_req_tr_fifo.push_back(rd_req_tr);
		
		this.rd_req_tr_id++;
	endfunction
	
	virtual function void write_fout(panda_axis_trans tr);
		this.fout_tr_fifo.push_back(tr);
	endfunction
	
	protected function void check_fout(int unsigned req_id = 0, panda_axis_trans res_tr = null, panda_axis_trans ref_tr = null);
		if(res_tr == null || ref_tr == null)
			return;
		
		if(res_tr.compare(ref_tr))
		begin
			`uvm_info(this.get_name(), $sformatf("[%0d]match", req_id), UVM_LOW)
			
			this.success_cnt++;
		end
		else
		begin
			`uvm_error(this.get_name(), $sformatf("[%0d]mismatch", req_id))
			
			this.failure_cnt++;
			
			res_tr.print();
			ref_tr.print();
		end
	endfunction
	
	`tue_component_default_constructor(ConvDataHubScoreboardBase)
	
endclass

class FmBufScoreboard extends ConvDataHubScoreboardBase #(
	.MEM_NAME("fmap_mem"),
	.RdReqTransAdapterType(FmRdReqTransAdapter)
);
	
	task main_phase(uvm_phase phase);
		forever
		begin
			FmRdReqTransAdapter fm_rd_req_tr;
			panda_axis_trans fmap_fout_tr;
			panda_axis_trans exp_fmap_fout;
			DataBlk data_blk;
			bit sfc_err;
			
			wait((this.rd_req_tr_fifo.size() > 0) && (this.fout_tr_fifo.size() > 0));
			
			fm_rd_req_tr = this.rd_req_tr_fifo.pop_front();
			fmap_fout_tr = this.fout_tr_fifo.pop_front();
			
			exp_fmap_fout = panda_axis_trans::type_id::create("exp_fmap_fout");
			exp_fmap_fout.len = fm_rd_req_tr.sfc_n_to_rd;
			exp_fmap_fout.data = new[fm_rd_req_tr.sfc_n_to_rd];
			
			data_blk = this.mem.data_blk.get_sub_data_blk(fm_rd_req_tr.sfc_row_baseaddr);
			
			if(data_blk == null)
			begin
				`uvm_error(this.get_name(), $sformatf("cannot get fmap_row(key = %0x)!", fm_rd_req_tr.sfc_row_baseaddr))
				
				continue;
			end
			
			sfc_err = 1'b0;
			
			for(int unsigned i = 0;i < fm_rd_req_tr.sfc_n_to_rd;i++)
			begin
				FmapSfc fmap_sfc;
				
				if(data_blk.get_sub_data_blk(i + fm_rd_req_tr.start_sfc_id) == null)
				begin
					sfc_err = 1'b1;
					
					`uvm_error(this.get_name(), "cannot get fmap_sfc!")
					
					break;
				end
				
				if(!$cast(fmap_sfc, data_blk.get_sub_data_blk(i + fm_rd_req_tr.start_sfc_id)))
					`uvm_fatal(this.get_name(), "cannot cast fmap_sfc!!!")
				
				if(fm_rd_req_tr.vld_data_n_foreach_sfc > fmap_sfc.get_size())
				begin
					sfc_err = 1'b1;
					`uvm_error(this.get_name(), "data_id out of index!")
					
					break;
				end
				
				exp_fmap_fout.data[i] = 1024'd0;
				
				for(int unsigned j = 0;j < fm_rd_req_tr.vld_data_n_foreach_sfc;j++)
					exp_fmap_fout.data[i][16*j+:16] = fmap_sfc.get_pt_by_index(j);
			end
			
			if(sfc_err)
				continue;
			
			this.check_fout(fm_rd_req_tr.id, fmap_fout_tr, exp_fmap_fout);
			
			this.chk_id++;
		end
	endtask
	
	`tue_component_default_constructor(FmBufScoreboard)
	`uvm_component_utils(FmBufScoreboard)
	
endclass

class KernalBufScoreboard extends ConvDataHubScoreboardBase #(
	.MEM_NAME("kernal_mem"),
	.RdReqTransAdapterType(KernalRdReqTransAdapter)
);
	
	local int unsigned now_cgrp_id_ofs; // 当前的通道组号偏移
	
	virtual function void write_rd_req(panda_axis_trans tr);
		KernalRdReqTransAdapter rd_req_tr;
		
		rd_req_tr = KernalRdReqTransAdapter::type_id::create();
		rd_req_tr.convert(tr);
		rd_req_tr.id = this.rd_req_tr_id;
		
		if(rd_req_tr.to_rst_buf)
		begin
			this.now_cgrp_id_ofs = rd_req_tr.cgrp_id_ofs;
			
			`uvm_info(this.get_name(), "get rst_buf", UVM_LOW)
		end
		else
		begin
			rd_req_tr.actual_cgrp_id_or_cgrpn += this.now_cgrp_id_ofs;
			
			this.rd_req_tr_fifo.push_back(rd_req_tr);
		end
		
		`panda_print_with(rd_req_tr, this.rd_req_tr_mcd, Util::get_object_printer())
		
		this.rd_req_tr_id++;
	endfunction
	
	task main_phase(uvm_phase phase);
		forever
		begin
			KernalRdReqTransAdapter kernal_rd_req_tr;
			panda_axis_trans kernal_fout_tr;
			panda_axis_trans exp_kernal_fout;
			DataBlk data_blk;
			bit sfc_err;
			
			wait((this.rd_req_tr_fifo.size() > 0) && (this.fout_tr_fifo.size() > 0));
			
			kernal_rd_req_tr = this.rd_req_tr_fifo.pop_front();
			kernal_fout_tr = this.fout_tr_fifo.pop_front();
			
			exp_kernal_fout = panda_axis_trans::type_id::create("exp_kernal_fout");
			exp_kernal_fout.len = kernal_rd_req_tr.sfc_n_to_rd;
			exp_kernal_fout.data = new[kernal_rd_req_tr.sfc_n_to_rd];
			
			data_blk = this.mem.data_blk.get_sub_data_blk(kernal_rd_req_tr.actual_cgrp_id_or_cgrpn);
			
			if(data_blk == null)
			begin
				`uvm_error(this.get_name(), $sformatf("cannot get kernal_cgrp(cgrp_id = %0d)!", kernal_rd_req_tr.actual_cgrp_id_or_cgrpn))
				
				continue;
			end
			
			data_blk = data_blk.get_sub_data_blk(kernal_rd_req_tr.wgtblk_id);
			
			if(data_blk == null)
			begin
				`uvm_error(this.get_name(), $sformatf("cannot get kernal_wgtblk(wgtblk_id = %0d)!", kernal_rd_req_tr.wgtblk_id))
				
				continue;
			end
			
			sfc_err = 1'b0;
			
			for(int unsigned i = 0;i < kernal_rd_req_tr.sfc_n_to_rd;i++)
			begin
				DataBlk sfc_base;
				KernalSfc sfc_this;
				
				sfc_base = data_blk.get_sub_data_blk(kernal_rd_req_tr.start_sfc_id + i);
				
				if(sfc_base == null)
				begin
					sfc_err = 1'b1;
					
					break;
				end
				
				if(!$cast(sfc_this, sfc_base))
				begin
					sfc_err = 1'b1;
					
					break;
				end
				
				exp_kernal_fout.data[i] = 1024'd0;
				
				for(int unsigned j = 0;j < kernal_rd_req_tr.vld_data_n_foreach_sfc;j++)
					exp_kernal_fout.data[i][16*j+:16] = sfc_this.get_pt_by_index(j);
			end
			
			if(sfc_err)
			begin
				`uvm_error(this.get_name(), $sformatf("cannot get kernal_sfc(start = %0d, len = %0d)!", kernal_rd_req_tr.start_sfc_id, kernal_rd_req_tr.sfc_n_to_rd))
				
				continue;
			end
			
			this.check_fout(kernal_rd_req_tr.id, kernal_fout_tr, exp_kernal_fout);
			
			this.chk_id++;
		end
	endtask
	
	`tue_component_default_constructor(KernalBufScoreboard)
	`uvm_component_utils(KernalBufScoreboard)
	
endclass

class FinalResScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	uvm_analysis_imp_final_res #(panda_axis_trans, FinalResScoreboard) final_res_port;
	
	local FmapCfg fmap_cfg;
	local KernalCfg kernal_cfg;
	local ConvCalCfg cal_cfg;
	local PandaMemoryAdapter fmap_mem;
	local PandaMemoryAdapter kernal_mem;
	
	local AbstractFinalResAdapter exp_res_adpt;
	
	local int final_res_tr_id;
	local int final_res_cmp_id_base;
	local int final_res_err_n;
	
	local int final_res_tr_mcd = UVM_STDOUT;
	local int exp_res_tr_mcd = UVM_STDOUT;
	
	local FmapOutPtCalProcListener cal_proc_listener = null;
	
	function void register_cal_proc_listener(FmapOutPtCalProcListener listener);
		this.cal_proc_listener = listener;
	endfunction
	
	function void set_final_res_tr_mcd(int mcd);
		this.final_res_tr_mcd = mcd;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.final_res_port = new("final_res_port", this);
		this.final_res_tr_id = 0;
		this.final_res_cmp_id_base = 0;
		this.final_res_err_n = 0;
		
		if(!uvm_config_db #(FmapCfg)::get(null, "", "fmap_cfg", this.fmap_cfg))
			`uvm_fatal(this.get_name(), "cannot get fmap_cfg!!!")
		if(!uvm_config_db #(KernalCfg)::get(null, "", "kernal_cfg", this.kernal_cfg))
			`uvm_fatal(this.get_name(), "cannot get kernal_cfg!!!")
		if(!uvm_config_db #(ConvCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		
		if(!uvm_config_db #(PandaMemoryAdapter)::get(null, "", "fmap_mem", this.fmap_mem))
			`uvm_fatal(this.get_name(), "cannot get fmap_mem!!!")
		if(!uvm_config_db #(PandaMemoryAdapter)::get(null, "", "kernal_mem", this.kernal_mem))
			`uvm_fatal(this.get_name(), "cannot get kernal_mem!!!")
		
		this.exp_res_tr_mcd = $fopen("exp_res_tr_log.txt");
		this.create_exp_res_adpt();
		this.gen_exp_final_res();
		`panda_print_with(this.exp_res_adpt, this.exp_res_tr_mcd, Util::get_object_printer())
		$fclose(this.exp_res_tr_mcd);
	endfunction
	
	virtual function void write_final_res(panda_axis_trans tr);
		AbstractFinalResAdapter adapter;
		
		adapter = null;
		
		if(this.cal_cfg.calfmt == CAL_FMT_FP16)
			adapter = Fp16FinalResAdapter::type_id::create();
		else
			`uvm_error(this.get_name(), "calfmt not supported!")
		
		if(adapter != null)
		begin
			adapter.id = this.final_res_tr_id;
			adapter.print_id_base = this.final_res_cmp_id_base;
			adapter.convert(tr);
			
			`panda_print_with(adapter, this.final_res_tr_mcd, Util::get_object_printer())
			
			// 比对最终结果的误差
			for(int i = 0;i < adapter.data_fifo.size();i++)
			begin
				ErrorValue err_v;
				
				err_v = adapter.data_fifo[i].cmp_err(exp_res_adpt.data_fifo[this.final_res_cmp_id_base + i]);
				err_v.id = this.final_res_cmp_id_base + i;
				
				if(err_v != null)
				begin
					if(!err_v.is_err_acceptable())
					begin
						`panda_print_with(err_v, this.final_res_tr_mcd, Util::get_object_printer())
						
						`uvm_error(this.get_name(), $sformatf("err_v is not acceptable, id = %0d", this.final_res_cmp_id_base + i))
						
						this.final_res_err_n++;
					end
				end
			end
			
			this.final_res_tr_id++;
			this.final_res_cmp_id_base += adapter.data_fifo.size();
		end
	endfunction
	
	task main_phase(uvm_phase phase);
		// blank
	endtask
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info(this.get_name(), $sformatf("final_res_n = %0d", this.final_res_cmp_id_base), UVM_LOW)
		`uvm_info(this.get_name(), $sformatf("final_res_err_n = %0d", this.final_res_err_n), UVM_LOW)
	endfunction
	
	local function void gen_exp_final_res();
		FmapBuilderCfg fmap_builder_cfg;
		KernalSetBuilderCfg kernal_set_builder_cfg;
		
		int unsigned ext_fmap_w; // 扩展特征图宽度
		int unsigned ext_fmap_h; // 扩展特征图高度
		int unsigned kernal_x_dilated; // (膨胀后)卷积核宽度或高度
		int unsigned ofmap_w; // 输出特征图宽度
		int unsigned ofmap_h; // 输出特征图高度
		
		int unsigned kernal_set_cgrp_id_base; // 核组起始通道组号
		
		Fmap fmap_this;
		
		fmap_builder_cfg = FmapBuilderCfg::type_id::create();
		kernal_set_builder_cfg = KernalSetBuilderCfg::type_id::create();
		
		fmap_builder_cfg.from_cfg(this.fmap_cfg, this.cal_cfg);
		kernal_set_builder_cfg.from_cfg(this.kernal_cfg, this.cal_cfg);
		
		ext_fmap_w = 
			this.fmap_cfg.fmap_w + this.cal_cfg.external_padding_left + this.cal_cfg.external_padding_right + 
			(this.fmap_cfg.fmap_w - 1) * this.cal_cfg.inner_padding_left_right;
		ext_fmap_h = 
			this.fmap_cfg.fmap_h + this.cal_cfg.external_padding_top + this.cal_cfg.external_padding_bottom + 
			(this.fmap_cfg.fmap_h - 1) * this.cal_cfg.inner_padding_top_bottom;
		kernal_x_dilated = 
			Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape) + 
			(Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape) - 1) * this.cal_cfg.kernal_dilation_n;
		ofmap_w = ((ext_fmap_w - kernal_x_dilated) / this.cal_cfg.conv_horizontal_stride) + 1;
		ofmap_h = ((ext_fmap_h - kernal_x_dilated) / this.cal_cfg.conv_vertical_stride) + 1;
		
		kernal_set_cgrp_id_base = 0;
		
		// 得到整个特征图
		if(!$cast(fmap_this, this.fmap_mem.data_blk))
		begin
			`uvm_error(this.get_name(), "cannot cast this.fmap_mem.data_blk -> fmap_this")
			
			return;
		end
		
		for(int unsigned s = 0;s < kernal_set_builder_cfg.total_kernal_set_n;s++)
		begin
			int unsigned logic_y_base;
			
			logic_y_base = 0;
			
			for(int unsigned oy = 0;oy < ofmap_h;oy++)
			begin
				int unsigned logic_x_base;
				
				logic_x_base = 0;
				
				for(int unsigned ox = 0;ox < ofmap_w;ox++)
				begin
					AbstractData ofmap_sfc[];
					int unsigned wgtblk_id;
					int unsigned logic_y_ofs;
					
					ofmap_sfc = new[kernal_set_builder_cfg.wgtblk_w_foreach_kernal_set[s]];
					wgtblk_id = 0;
					logic_y_ofs = 0;
					
					foreach(ofmap_sfc[_i])
					begin
						ofmap_sfc[_i] = this.create_abst_data();
					end
					
					for(int unsigned ky = 0;ky < Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape);ky++)
					begin
						int unsigned logic_x_ofs;
						
						logic_x_ofs = 0;
						
						for(int unsigned kx = 0;kx < Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape);kx++)
						begin
							int unsigned logic_x;
							int unsigned logic_y;
							int unsigned phy_x;
							int unsigned phy_y;
							bit pt_invld;
							
							// 坐标转换: (logic_x, logic_y) -> {(phy_x, phy_y), pt_invld}
							logic_x = logic_x_base + logic_x_ofs;
							logic_y = logic_y_base + logic_y_ofs;
							pt_invld = this.convert_logic_pos(logic_x, logic_y, phy_x, phy_y);
							
							if(!pt_invld)
							begin
								for(int unsigned cg = 0;cg < kernal_set_builder_cfg.cgrpn_foreach_kernal_set[s];cg++)
								begin
									DataBlk kernal_data_blk;
									DataBlk fmap_data_blk;
									int unsigned fmap_build_rid;
									int unsigned fmap_actual_rid;
									
									FmapSfc fmap_sfc;
									
									bit kernal_sfc_err_flag;
									
									// 得到整个卷积核权重
									kernal_data_blk = this.kernal_mem.data_blk;
									
									// 取出卷积核通道组
									kernal_data_blk = kernal_data_blk.get_sub_data_blk(kernal_set_cgrp_id_base + cg);
									
									if(kernal_data_blk == null)
									begin
										`uvm_error(this.get_name(), $sformatf("cannot get kernal_cgrp(set = %0d, cg = %0d, id = %0d)", s, cg, kernal_set_cgrp_id_base + cg))
										
										break;
									end
									
									// 取出权重块
									kernal_data_blk = kernal_data_blk.get_sub_data_blk(wgtblk_id);
									
									if(kernal_data_blk == null)
									begin
										`uvm_error(this.get_name(), $sformatf("cannot get kernal_wgtblk(wgtblk_id = %0d)", wgtblk_id))
										
										break;
									end
									
									// 检查权重块宽度
									if(kernal_data_blk.num_of_sub_data_blk() != kernal_set_builder_cfg.wgtblk_w_foreach_kernal_set[s])
									begin
										`uvm_error(this.get_name(), $sformatf("Expected wgtblk_w is %0d, but it's %0d", kernal_set_builder_cfg.wgtblk_w_foreach_kernal_set[s], kernal_data_blk.num_of_sub_data_blk()))
										
										break;
									end
									
									// 取出特征图表面行
									fmap_build_rid = (((this.cal_cfg.is_grp_conv_mode ? kernal_set_cgrp_id_base:0) + cg) * this.fmap_cfg.fmap_h) + phy_y;
									fmap_actual_rid = fmap_this.rid_hash[fmap_build_rid];
									fmap_data_blk = fmap_this.get_sub_data_blk(fmap_actual_rid);
									
									if(fmap_data_blk == null)
									begin
										`uvm_error(this.get_name(), $sformatf("cannot get fmap_sfc_row(set = %0d, cg = %0d, phy_y = %0d, actual_rid = %0d)", s, cg, phy_y, fmap_actual_rid))
										
										break;
									end
									
									// 取出特征图表面
									fmap_data_blk = fmap_data_blk.get_sub_data_blk(phy_x);
									
									if(fmap_data_blk == null)
									begin
										`uvm_error(this.get_name(), $sformatf("cannot get fmap_sfc(phy_x = %0d)", phy_x))
										
										break;
									end
									
									if(!$cast(fmap_sfc, fmap_data_blk))
									begin
										`uvm_error(this.get_name(), "cannot cast fmap_data_blk -> fmap_sfc")
										
										break;
									end
									
									// 检查特征图表面深度
									if(fmap_sfc.get_size() != fmap_builder_cfg.sfc_data_n_foreach_fmrow[fmap_build_rid])
									begin
										`uvm_error(this.get_name(), $sformatf("Expected fmap_sfc_depth is %0d, but it's %0d", fmap_builder_cfg.sfc_data_n_foreach_fmrow[fmap_build_rid], fmap_sfc.get_size()))
										
										break;
									end
									
									// 对表面进行乘加计算
									kernal_sfc_err_flag = 1'b0;
									
									for(int unsigned mac_k = 0;mac_k < kernal_set_builder_cfg.wgtblk_w_foreach_kernal_set[s];mac_k++)
									begin
										DataBlk kernal_sfc_base;
										KernalSfc kernal_sfc_this;
										AbstractData sfc_chn_mac_res;
										
										sfc_chn_mac_res = this.create_abst_data();
										
										// 取出卷积核表面
										kernal_sfc_base = kernal_data_blk.get_sub_data_blk(mac_k);
										
										if(kernal_sfc_base == null)
										begin
											`uvm_error(this.get_name(), $sformatf("cannot get kernal_sfc(mac_k = %0d)", mac_k))
											
											kernal_sfc_err_flag = 1'b1;
											
											break;
										end
										
										if(!$cast(kernal_sfc_this, kernal_sfc_base))
										begin
											`uvm_error(this.get_name(), "cannot cast kernal_sfc_base -> kernal_sfc_this")
											
											kernal_sfc_err_flag = 1'b1;
											
											break;
										end
										
										// 检查卷积核表面深度
										if(kernal_sfc_this.get_size() != kernal_set_builder_cfg.depth_foreach_kernal_cgrp[kernal_set_cgrp_id_base + cg])
										begin
											`uvm_error(this.get_name(), $sformatf("Expected kernal_sfc_depth is %0d, but it's %0d", kernal_set_builder_cfg.depth_foreach_kernal_cgrp[kernal_set_cgrp_id_base + cg], kernal_sfc_this.get_size()))
											
											kernal_sfc_err_flag = 1'b1;
											
											break;
										end
										
										// 检查特征图和卷积核表面深度是否匹配
										if(kernal_set_builder_cfg.depth_foreach_kernal_cgrp[kernal_set_cgrp_id_base + cg] != fmap_builder_cfg.sfc_data_n_foreach_fmrow[fmap_build_rid])
										begin
											`uvm_error(this.get_name(), $sformatf("sfc_depth mismatch(kernal: %0d, fmap: %0d)", kernal_set_builder_cfg.depth_foreach_kernal_cgrp[kernal_set_cgrp_id_base + cg], fmap_builder_cfg.sfc_data_n_foreach_fmrow[fmap_build_rid]))
											
											kernal_sfc_err_flag = 1'b1;
											
											break;
										end
										
										for(int unsigned mac_c = 0;mac_c < kernal_set_builder_cfg.depth_foreach_kernal_cgrp[kernal_set_cgrp_id_base + cg];mac_c++)
										begin
											sfc_chn_mac_res.add_assign(fmap_sfc.data[mac_c].mul(kernal_sfc_this.data[mac_c]));
										end
										
										ofmap_sfc[mac_k].add_assign(sfc_chn_mac_res);
										
										// 跟踪输出特征图某个点的累加计算过程
										if(this.cal_proc_listener != null)
											this.cal_proc_listener.on_upd_out_pt_type1(
												sfc_chn_mac_res,
												s, oy, ox, ky, kx, cg, mac_k
											);
									end
									
									if(kernal_sfc_err_flag)
										break;
								end
							end
							
							wgtblk_id++;
							logic_x_ofs += (this.cal_cfg.kernal_dilation_n + 1);
						end
						
						logic_y_ofs += (this.cal_cfg.kernal_dilation_n + 1);
					end
					
					// 添加输出表面数据
					this.exp_res_adpt.put_data(ofmap_sfc);
					
					// 添加打印信息
					for(int unsigned _i = 0;_i < kernal_set_builder_cfg.wgtblk_w_foreach_kernal_set[s];_i++)
					begin
						this.exp_res_adpt.print_context.push_back($sformatf("kset%0d, oy%0d, ox%0d, sfc_i%0d", s, oy, ox, _i));
					end
					
					logic_x_base += this.cal_cfg.conv_horizontal_stride;
				end
				
				logic_y_base += this.cal_cfg.conv_vertical_stride;
			end
			
			kernal_set_cgrp_id_base += kernal_set_builder_cfg.cgrpn_foreach_kernal_set[s];
		end
	endfunction
	
	local function void create_exp_res_adpt();
		if(this.cal_cfg.calfmt == CAL_FMT_FP16)
		begin
			this.exp_res_adpt = Fp16FinalResAdapter::type_id::create();
		end
		else
			`uvm_error(this.get_name(), "calfmt not supported!")
	endfunction
	
	local function AbstractData create_abst_data();
		AbstractData abst_data;
		
		abst_data = null;
		
		if(this.cal_cfg.calfmt == CAL_FMT_FP16)
		begin
			abst_data = PackedReal::type_id::create();
			abst_data.set_to_zero();
		end
		else
			`uvm_error(this.get_name(), "calfmt not supported!")
		
		return abst_data;
	endfunction
	
	local function bit convert_logic_pos(
		input int unsigned logic_x, input int unsigned logic_y,
		output int unsigned phy_x, output int unsigned phy_y
	);
		int unsigned ext_i_bottom; // 扩展后特征图的垂直边界
		int unsigned ext_j_right; // 扩展后特征图的水平边界
		
		ext_i_bottom = 
			this.cal_cfg.external_padding_top + 
			this.fmap_cfg.fmap_h + 
			(this.fmap_cfg.fmap_h - 1) * this.cal_cfg.inner_padding_top_bottom - 1;
		ext_j_right = 
			this.cal_cfg.external_padding_left + 
			this.fmap_cfg.fmap_w + 
			(this.fmap_cfg.fmap_w - 1) * this.cal_cfg.inner_padding_left_right - 1;
		
		if(
			((logic_x >= this.cal_cfg.external_padding_left) && (logic_x <= ext_j_right)) && 
			(((logic_x - this.cal_cfg.external_padding_left) % (this.cal_cfg.inner_padding_left_right + 1)) == 0)
		)
			phy_x = (logic_x - this.cal_cfg.external_padding_left) / (this.cal_cfg.inner_padding_left_right + 1);
		else
			return 1'b1;
		
		if(
			((logic_y >= this.cal_cfg.external_padding_top) && (logic_y <= ext_i_bottom)) && 
			(((logic_y - this.cal_cfg.external_padding_top) % (this.cal_cfg.inner_padding_top_bottom + 1)) == 0)
		)
			phy_y = (logic_y - this.cal_cfg.external_padding_top) / (this.cal_cfg.inner_padding_top_bottom + 1);
		else
			return 1'b1;
		
		return 1'b0;
	endfunction
	
	`tue_component_default_constructor(FinalResScoreboard)
	`uvm_component_utils(FinalResScoreboard)
	
endclass

class MidResAcmltCalScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	uvm_analysis_imp_acmlt_in #(panda_axis_trans, MidResAcmltCalScoreboard) acmlt_in_port;
	
	local mailbox #(panda_axis_trans) acmlt_in_mb;
	
	local FmapCfg fmap_cfg;
	local KernalCfg kernal_cfg;
	local ConvCalCfg cal_cfg;
	
	local FmapBuilderCfg fmap_builder_cfg;
	local KernalSetBuilderCfg kernal_set_builder_cfg;
	
	local FmapOutPtCalProcListener cal_proc_listener = null;
	
	function void register_cal_proc_listener(FmapOutPtCalProcListener listener);
		this.cal_proc_listener = listener;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.acmlt_in_port = new("acmlt_in_port", this);
		
		this.acmlt_in_mb = new();
		
		if(!uvm_config_db #(FmapCfg)::get(null, "", "fmap_cfg", this.fmap_cfg))
			`uvm_fatal(this.get_name(), "cannot get fmap_cfg!!!")
		if(!uvm_config_db #(KernalCfg)::get(null, "", "kernal_cfg", this.kernal_cfg))
			`uvm_fatal(this.get_name(), "cannot get kernal_cfg!!!")
		if(!uvm_config_db #(ConvCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		
		this.fmap_builder_cfg = FmapBuilderCfg::type_id::create();
		this.kernal_set_builder_cfg = KernalSetBuilderCfg::type_id::create();
		
		this.fmap_builder_cfg.from_cfg(this.fmap_cfg, this.cal_cfg);
		this.kernal_set_builder_cfg.from_cfg(this.kernal_cfg, this.cal_cfg);
	endfunction
	
	virtual function void write_acmlt_in(panda_axis_trans tr);
		if(!this.acmlt_in_mb.try_put(tr))
			`uvm_error(this.get_name(), "cannot put acmlt_in_mb!")
	endfunction
	
	task main_phase(uvm_phase phase);
		int unsigned ext_fmap_w; // 扩展特征图宽度
		int unsigned ext_fmap_h; // 扩展特征图高度
		int unsigned kernal_x_dilated; // (膨胀后)卷积核宽度或高度
		int unsigned ofmap_w; // 输出特征图宽度
		int unsigned ofmap_h; // 输出特征图高度
		
		ext_fmap_w = 
			this.fmap_cfg.fmap_w + this.cal_cfg.external_padding_left + this.cal_cfg.external_padding_right + 
			(this.fmap_cfg.fmap_w - 1) * this.cal_cfg.inner_padding_left_right;
		ext_fmap_h = 
			this.fmap_cfg.fmap_h + this.cal_cfg.external_padding_top + this.cal_cfg.external_padding_bottom + 
			(this.fmap_cfg.fmap_h - 1) * this.cal_cfg.inner_padding_top_bottom;
		kernal_x_dilated = 
			Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape) + 
			(Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape) - 1) * this.cal_cfg.kernal_dilation_n;
		ofmap_w = ((ext_fmap_w - kernal_x_dilated) / this.cal_cfg.conv_horizontal_stride) + 1;
		ofmap_h = ((ext_fmap_h - kernal_x_dilated) / this.cal_cfg.conv_vertical_stride) + 1;
		
		for(int unsigned s = 0;s < this.kernal_set_builder_cfg.total_kernal_set_n;s++)
		begin
			int unsigned logic_y_base;
			
			logic_y_base = 0;
			
			for(int unsigned oy = 0;oy < ofmap_h;oy++)
			begin
				for(int unsigned cg = 0;cg < this.kernal_set_builder_cfg.cgrpn_foreach_kernal_set[s];cg++)
				begin
					int unsigned logic_y_ofs;
					
					logic_y_ofs = 0;
					
					for(int unsigned ky = 0;ky < Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape);ky++)
					begin
						if(this.is_row_vld(logic_y_base + logic_y_ofs))
						begin
							for(int unsigned kx = 0;kx < Util::kernal_sz_t_to_w_h(this.kernal_cfg.kernal_shape);kx++)
							begin
								for(int unsigned ox = 0;ox < ofmap_w;ox++)
								begin
									for(int unsigned r = 0;r < this.cal_cfg.cal_round;r++)
									begin
										panda_axis_trans axis_tr;
										
										this.acmlt_in_mb.get(axis_tr);
										
										if(this.cal_proc_listener != null)
											this.cal_proc_listener.on_upd_out_pt_type0(axis_tr, s, oy, ox, ky, kx, cg, r);
									end
								end
							end
						end
						
						logic_y_ofs += (this.cal_cfg.kernal_dilation_n + 1);
					end
				end
				
				logic_y_base += this.cal_cfg.conv_vertical_stride;
			end
		end
	endtask
	
	local function bit is_row_vld(int unsigned logic_y);
		int unsigned ext_i_bottom; // 扩展后特征图的垂直边界
		
		ext_i_bottom = 
			this.cal_cfg.external_padding_top + 
			this.fmap_cfg.fmap_h + 
			(this.fmap_cfg.fmap_h - 1) * this.cal_cfg.inner_padding_top_bottom - 1;
		
		if(
			((logic_y >= this.cal_cfg.external_padding_top) && (logic_y <= ext_i_bottom)) && 
			(((logic_y - this.cal_cfg.external_padding_top) % (this.cal_cfg.inner_padding_top_bottom + 1)) == 0)
		)
			return 1'b1;
		else
			return 1'b0;
	endfunction
	
	`tue_component_default_constructor(MidResAcmltCalScoreboard)
	`uvm_component_utils(MidResAcmltCalScoreboard)
	
endclass

`endif
