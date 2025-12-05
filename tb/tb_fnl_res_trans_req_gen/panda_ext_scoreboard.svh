`ifndef __PANDA_EXT_SCOREBOARD_H

`define __PANDA_EXT_SCOREBOARD_H

`uvm_analysis_imp_decl(_blk_ctrl)
`uvm_analysis_imp_decl(_req)

class FnlResTransReqGenScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	uvm_analysis_imp_blk_ctrl #(panda_blk_ctrl_abstract_trans, FnlResTransReqGenScoreboard) blk_ctrl_port;
	uvm_analysis_imp_req #(panda_axis_trans, FnlResTransReqGenScoreboard) req_port;
	
	int atomic_k = 8; // 核并行数
	
	local int unsigned blk_ctrl_tr_id;
	local int unsigned req_tr_id;
	local int unsigned match_tr_n;
	local int unsigned mismatch_tr_n;
	
	local int blk_ctrl_tr_mcd = UVM_STDOUT;
	local int req_tr_mcd = UVM_STDOUT;
	
	local mailbox #(panda_fnl_res_trans_req_gen_blk_ctrl_trans) blk_ctrl_tr_mb;
	local mailbox #(DMAS2MMReqTransAdapter) req_mb;
	
	function void set_blk_ctrl_tr_mcd(int mcd);
		this.blk_ctrl_tr_mcd = mcd;
	endfunction
	
	function void set_req_tr_mcd(int mcd);
		this.req_tr_mcd = mcd;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.blk_ctrl_port = new("blk_ctrl_port", this);
		this.req_port = new("req_port", this);
		
		this.blk_ctrl_tr_id = 0;
		this.req_tr_id = 0;
		this.match_tr_n = 0;
		this.mismatch_tr_n = 0;
		
		this.blk_ctrl_tr_mb = new();
		this.req_mb = new();
	endfunction
	
	virtual function void write_blk_ctrl(panda_blk_ctrl_abstract_trans tr);
		panda_fnl_res_trans_req_gen_blk_ctrl_trans blk_ctrl_tr;
		
		if(!$cast(blk_ctrl_tr, tr))
			`uvm_fatal(this.get_name(), "cannot cast panda_blk_ctrl_abstract_trans to panda_fnl_res_trans_req_gen_blk_ctrl_trans!")
		
		blk_ctrl_tr.id = this.blk_ctrl_tr_id;
		`panda_print_with(blk_ctrl_tr, this.blk_ctrl_tr_mcd, Util::get_object_printer())
		
		if(!this.blk_ctrl_tr_mb.try_put(blk_ctrl_tr))
			`uvm_error(this.get_name(), "cannot put blk_ctrl_tr")
		
		this.blk_ctrl_tr_id++;
	endfunction
	
	virtual function void write_req(panda_axis_trans tr);
		DMAS2MMReqTransAdapter req_adapter;
		
		req_adapter = DMAS2MMReqTransAdapter::type_id::create("res_cmd_req");
		req_adapter.convert(tr);
		req_adapter.tr_id = this.req_tr_id;
		
		`panda_print_with(req_adapter, this.req_tr_mcd, Util::get_object_printer())
		
		if(!this.req_mb.try_put(req_adapter))
			`uvm_error(this.get_name(), "cannot put req_adapter")
		
		this.req_tr_id++;
	endfunction
	
	task main_phase(uvm_phase phase);
		int unsigned chk_blk_ctrl_tr_id;
		
		chk_blk_ctrl_tr_id = 0;
		
		forever
		begin
			panda_fnl_res_trans_req_gen_blk_ctrl_trans blk_ctrl_tr;
			
			int unsigned ochn_rgn_n; // 输出通道域个数
			int unsigned max_ochn_rgn_depth; // 输出通道域的最大深度
			int unsigned ochn_rgn_ofsaddr; // 输出通道域偏移地址
			int unsigned ochn_id_base; // 输出通道号基准
			
			this.blk_ctrl_tr_mb.get(blk_ctrl_tr);
			
			ochn_rgn_n = 
				blk_ctrl_tr.is_grp_conv_mode ? 
					blk_ctrl_tr.group_n:
					(
						(blk_ctrl_tr.kernal_num_n / blk_ctrl_tr.max_wgtblk_w) + 
						((blk_ctrl_tr.kernal_num_n % blk_ctrl_tr.max_wgtblk_w) ? 1:0)
					);
			max_ochn_rgn_depth = 
				blk_ctrl_tr.is_grp_conv_mode ? 
					blk_ctrl_tr.n_foreach_group:
					blk_ctrl_tr.max_wgtblk_w;
			ochn_rgn_ofsaddr = 0;
			ochn_id_base = 0;
			
			for(int unsigned r = 0;r < ochn_rgn_n;r++)
			begin
				for(int unsigned y = 0;y < blk_ctrl_tr.ofmap_h;y++)
				begin
					int unsigned ochn_id_ofs; // 输出通道号偏移
					int unsigned sub_sfc_row_ofsaddr; // 输出特征图子表面行偏移地址
					
					ochn_id_ofs = 0;
					sub_sfc_row_ofsaddr = 0;
					
					do
					begin
						int unsigned sub_sfc_row_depth; // 输出特征图子表面行深度
						DMAS2MMReqTransAdapter exp_tr; // 参考结果
						DMAS2MMReqTransAdapter res_tr; // 运行结果
						
						if((ochn_id_base + ochn_id_ofs + this.atomic_k) >= blk_ctrl_tr.kernal_num_n)
							sub_sfc_row_depth = blk_ctrl_tr.kernal_num_n - (ochn_id_base + ochn_id_ofs);
						else if((ochn_id_ofs + this.atomic_k) >= max_ochn_rgn_depth)
							sub_sfc_row_depth = max_ochn_rgn_depth - ochn_id_ofs;
						else
							sub_sfc_row_depth = this.atomic_k;
						
						exp_tr = DMAS2MMReqTransAdapter::type_id::create("exp_cmd_req");
						exp_tr.btt = blk_ctrl_tr.ofmap_w * Util::ofmap_data_type_to_int(blk_ctrl_tr.ofmap_data_type) * sub_sfc_row_depth;
						exp_tr.baseaddr = 
							blk_ctrl_tr.ofmap_baseaddr + ochn_rgn_ofsaddr + sub_sfc_row_ofsaddr + 
							(y * exp_tr.btt);
						exp_tr.trans_type = "Incr";
						
						this.req_mb.get(res_tr);
						
						if(res_tr.compare(exp_tr))
						begin
							`uvm_info(this.get_name(), $sformatf("match, cmd_id = %0d", res_tr.cmd_id), UVM_LOW)
							
							this.match_tr_n++;
						end
						else
						begin
							`uvm_error(this.get_name(), $sformatf("mismatch, cmd_id = %0d", res_tr.cmd_id))
							
							res_tr.print();
							exp_tr.print();
							
							this.mismatch_tr_n++;
						end
						
						ochn_id_ofs += this.atomic_k;
						sub_sfc_row_ofsaddr += 
							(
								blk_ctrl_tr.ofmap_w * blk_ctrl_tr.ofmap_h * Util::ofmap_data_type_to_int(blk_ctrl_tr.ofmap_data_type) * 
								this.atomic_k
							);
					end
					while(
						((ochn_id_base + ochn_id_ofs) < blk_ctrl_tr.kernal_num_n) && 
						(ochn_id_ofs < max_ochn_rgn_depth)
					);
				end
				
				ochn_rgn_ofsaddr += 
					(
						blk_ctrl_tr.ofmap_w * blk_ctrl_tr.ofmap_h * Util::ofmap_data_type_to_int(blk_ctrl_tr.ofmap_data_type) * 
						max_ochn_rgn_depth
					);
				ochn_id_base += max_ochn_rgn_depth;
			end
			
			`uvm_info(this.get_name(), $sformatf("chk_fns, id = %0d", chk_blk_ctrl_tr_id), UVM_LOW)
			
			chk_blk_ctrl_tr_id++;
		end
	endtask
	
	function void check_phase(uvm_phase phase);
		if(this.blk_ctrl_tr_mb.num())
			`uvm_error(this.get_name(), "blk_ctrl_tr_mb is not empty")
		else
			`uvm_info(this.get_name(), "blk_ctrl_tr_mb is empty", UVM_LOW)
		
		if(this.req_mb.num())
			`uvm_error(this.get_name(), "req_mb is not empty")
		else
			`uvm_info(this.get_name(), "req_mb is empty", UVM_LOW)
	endfunction
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		if(this.match_tr_n == this.req_tr_id)
			`uvm_info(this.get_name(), $sformatf("get %0d tr, match = %0d, mismatch = %0d", this.req_tr_id, this.match_tr_n, this.mismatch_tr_n), UVM_LOW)
		else
			`uvm_error(this.get_name(), $sformatf("get %0d tr, match = %0d, mismatch = %0d", this.req_tr_id, this.match_tr_n, this.mismatch_tr_n))
	endfunction
	
	`tue_component_default_constructor(FnlResTransReqGenScoreboard)
	`uvm_component_utils(FnlResTransReqGenScoreboard)
	
endclass

`endif
