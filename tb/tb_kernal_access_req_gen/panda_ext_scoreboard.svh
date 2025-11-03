`ifndef __PANDA_EXT_SCOREBOARD_H

`define __PANDA_EXT_SCOREBOARD_H

`uvm_analysis_imp_decl(_blk_ctrl)
`uvm_analysis_imp_decl(_kwgtblk_rd_req)

class KernalAccessReqGenScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	uvm_analysis_imp_blk_ctrl #(panda_blk_ctrl_abstract_trans, KernalAccessReqGenScoreboard) blk_ctrl_port;
	uvm_analysis_imp_kwgtblk_rd_req #(panda_axis_trans, KernalAccessReqGenScoreboard) kwgtblk_rd_req_port;
	
	int atomic_c = 4; // 通道并行数
	int atomic_k = 8; // 核并行数
	
	local int unsigned blk_ctrl_tr_id;
	local int blk_ctrl_tr_mcd = UVM_STDOUT;
	local int unsigned rd_req_tr_id;
	local int rd_req_tr_mcd = UVM_STDOUT;
	
	local panda_kernal_access_req_gen_blk_ctrl_trans blk_ctrl_tr_fifo[$];
	local KernalRdReqTransAdapter kwgtblk_rd_req_tr_fifo[$];
	
	static function int kernal_sz_t_to_int(kernal_sz_t sz);
		case(sz)
			KBUFGRPSZ_1x1: return 1 * 1;
			KBUFGRPSZ_3x3: return 3 * 3;
			KBUFGRPSZ_5x5: return 5 * 5;
			KBUFGRPSZ_7x7: return 7 * 7;
			KBUFGRPSZ_9x9: return 9 * 9;
			KBUFGRPSZ_11x11: return 11 * 11;
		endcase
	endfunction
	
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
		`panda_print(blk_ctrl_tr, this.blk_ctrl_tr_mcd)
		
		this.blk_ctrl_tr_fifo.push_back(blk_ctrl_tr);
		
		this.blk_ctrl_tr_id++;
	endfunction
	
	virtual function void write_kwgtblk_rd_req(panda_axis_trans tr);
		KernalRdReqTransAdapter rd_req_adapter;
		
		rd_req_adapter = new(tr);
		rd_req_adapter.id = this.rd_req_tr_id;
		
		`panda_print(rd_req_adapter, this.rd_req_tr_mcd)
		
		this.kwgtblk_rd_req_tr_fifo.push_back(rd_req_adapter);
		
		this.rd_req_tr_id++;
	endfunction
	
	function void check_phase(uvm_phase phase);
		int blk_ctrl_tr_i;
		KernalRdReqTransAdapter exp_rd_req_tr;
		KernalRdReqTransAdapter res_rd_req_tr;
		
		super.check_phase(phase);
		
		blk_ctrl_tr_i = 0;
		
		while(this.blk_ctrl_tr_fifo.size() > 0)
		begin
			panda_kernal_access_req_gen_blk_ctrl_trans blk_ctrl_tr;
			int kernal_set_n; // 核组总数
			int cgrpn; // 通道组总数
			int kernal_set_ofs_addr; // 核组偏移地址
			
			blk_ctrl_tr = this.blk_ctrl_tr_fifo.pop_front();
			
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
				
				exp_rd_req_tr = new();
				
				exp_rd_req_tr.to_rst_buf = 1'b1;
				exp_rd_req_tr.actual_cgrp_id_or_cgrpn = cgrpn;
				exp_rd_req_tr.cgrp_id_ofs = k * cgrpn;
				
				res_rd_req_tr = this.kwgtblk_rd_req_tr_fifo.pop_front();
				
				if(res_rd_req_tr != null)
				begin
					if(exp_rd_req_tr.compare(res_rd_req_tr))
						`uvm_info(this.get_name(), $sformatf("rst_check tr%0d kset%0d Match", blk_ctrl_tr_i, k), UVM_LOW)
					else
						`uvm_error(this.get_name(), $sformatf("rst_check tr%0d kset%0d Mismatch", blk_ctrl_tr_i, k))
				end
				else
					`uvm_error(this.get_name(), $sformatf("rst_check tr%0d kset%0d NULL", blk_ctrl_tr_i, k))
				
				for(int h = 0;h < blk_ctrl_tr.ofmap_h;h++)
				begin
					int cgrp_ofs_addr; // 通道组偏移地址
					
					cgrp_ofs_addr = 0;
					
					for(int c = 0;c < cgrpn;c++)
					begin
						int sfc_depth; // 表面深度
						
						if(c == (cgrpn - 1))
							sfc_depth = 
								(blk_ctrl_tr.kernal_chn_n % this.atomic_c) ? 
									(blk_ctrl_tr.kernal_chn_n % this.atomic_c):
									this.atomic_c;
						else
							sfc_depth = this.atomic_c;
						
						for(int w = 0;w < KernalAccessReqGenScoreboard::kernal_sz_t_to_int(blk_ctrl_tr.kernal_shape);w++)
						begin
							exp_rd_req_tr = new();
							
							exp_rd_req_tr.to_rst_buf = 1'b0;
							exp_rd_req_tr.actual_cgrp_id_or_cgrpn = c;
							exp_rd_req_tr.wgtblk_id = w;
							exp_rd_req_tr.start_sfc_id = 0;
							exp_rd_req_tr.sfc_n_to_rd = kwgtblk_w;
							exp_rd_req_tr.kernal_cgrp_baseaddr = 
								blk_ctrl_tr.kernal_wgt_baseaddr + kernal_set_ofs_addr + cgrp_ofs_addr;
							exp_rd_req_tr.kernal_cgrp_btt = 
								KernalAccessReqGenScoreboard::kernal_sz_t_to_int(blk_ctrl_tr.kernal_shape) * 
								kwgtblk_w * sfc_depth * (blk_ctrl_tr.is_16bit_wgt ? 2:1);
							exp_rd_req_tr.sfc_n_foreach_wgtblk = kwgtblk_w;
							exp_rd_req_tr.vld_data_n_foreach_sfc = sfc_depth;
							
							res_rd_req_tr = this.kwgtblk_rd_req_tr_fifo.pop_front();
							
							if(res_rd_req_tr != null)
							begin
								if(exp_rd_req_tr.compare(res_rd_req_tr))
									`uvm_info(this.get_name(), $sformatf("normal_check tr%0d kset%0d ofmap_h%0d cgrp%0d blk%0d Match", blk_ctrl_tr_i, k, h, c, w), UVM_LOW)
								else
									`uvm_error(this.get_name(), $sformatf("normal_check tr%0d kset%0d ofmap_h%0d cgrp%0d blk%0d Mismatch", blk_ctrl_tr_i, k, h, c, w))
							end
							else
								`uvm_error(this.get_name(), $sformatf("normal_check tr%0d kset%0d ofmap_h%0d cgrp%0d blk%0d NULL", blk_ctrl_tr_i, k, h, c, w))
						end
						
						cgrp_ofs_addr += 
							KernalAccessReqGenScoreboard::kernal_sz_t_to_int(blk_ctrl_tr.kernal_shape) * 
							kwgtblk_w * sfc_depth * (blk_ctrl_tr.is_16bit_wgt ? 2:1);
					end
				end
				
				kernal_set_ofs_addr += 
					KernalAccessReqGenScoreboard::kernal_sz_t_to_int(blk_ctrl_tr.kernal_shape) * 
					kwgtblk_w * 
					(blk_ctrl_tr.is_grp_conv_mode ? blk_ctrl_tr.n_foreach_group:blk_ctrl_tr.kernal_chn_n) * 
					(blk_ctrl_tr.is_16bit_wgt ? 2:1);
			end
			
			res_rd_req_tr = this.kwgtblk_rd_req_tr_fifo.pop_front();
			
			if(res_rd_req_tr != null)
			begin
				if(res_rd_req_tr.to_rst_buf)
					`uvm_info(this.get_name(), $sformatf("rst_check tr%0d Match", blk_ctrl_tr_i), UVM_LOW)
				else
					`uvm_error(this.get_name(), $sformatf("rst_check tr%0d Mismatch", blk_ctrl_tr_i))
			end
			else
				`uvm_error(this.get_name(), $sformatf("rst_check tr%0d NULL", blk_ctrl_tr_i))
			
			blk_ctrl_tr_i++;
		end
		
		if(this.kwgtblk_rd_req_tr_fifo.size() == 0)
			`uvm_info(this.get_name(), "kwgtblk_rd_req_tr_fifo size Match", UVM_LOW)
		else
			`uvm_error(this.get_name(), "kwgtblk_rd_req_tr_fifo size Mismatch")
	endfunction
	
	`tue_component_default_constructor(KernalAccessReqGenScoreboard)
	`uvm_component_utils(KernalAccessReqGenScoreboard)
	
endclass

`endif
