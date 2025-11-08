`ifndef __PANDA_EXT_SCOREBOARD_H

`define __PANDA_EXT_SCOREBOARD_H

`uvm_analysis_imp_decl(_blk_ctrl)
`uvm_analysis_imp_decl(_rd_req)

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
		`panda_print(blk_ctrl_tr, this.blk_ctrl_tr_mcd)
		
		this.blk_ctrl_fifo.push_back(blk_ctrl_tr);
		
		this.blk_ctrl_tr_id++;
	endfunction
	
	virtual function void write_rd_req(panda_axis_trans tr);
		FmRdReqTransAdapter rd_req_adapter;
		
		rd_req_adapter = FmRdReqTransAdapter::type_id::create();
		rd_req_adapter.convert(tr);
		rd_req_adapter.id = this.rd_req_tr_id;
		
		`panda_print(rd_req_adapter, this.rd_req_tr_mcd)
		
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
						
						convert_logic_y(blk_ctrl_tr, logic_y_base + logic_y_ofs, phy_y, row_masked);
						
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
								(blk_ctrl_tr.is_grp_conv_mode ? 0:(s * blk_ctrl_tr.data_size_foreach_group)) + 
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
	
	function void convert_logic_y(panda_fmap_sfc_row_access_req_gen_blk_ctrl_trans blk_ctrl_tr, int logic_y,
		output int phy_y, output bit row_masked);
		if(
			(logic_y >= blk_ctrl_tr.external_padding_top && logic_y <= blk_ctrl_tr.ext_i_bottom) && 
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

`endif
