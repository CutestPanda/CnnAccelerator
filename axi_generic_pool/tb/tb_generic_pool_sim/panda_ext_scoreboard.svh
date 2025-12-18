`ifndef __PANDA_EXT_SCOREBOARD_H

`define __PANDA_EXT_SCOREBOARD_H

`uvm_analysis_imp_decl(_final_res)
`uvm_analysis_imp_decl(_req)

class FinalResScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	uvm_analysis_imp_final_res #(panda_axis_trans, FinalResScoreboard) final_res_port;
	
	local mailbox #(AbstractFinalResAdapter) final_res_mb;
	
	local FmapCfg fmap_cfg;
	local PoolCalCfg cal_cfg;
	
	local PandaMemoryAdapter fmap_mem;
	
	local AbstractFinalResAdapter exp_res_adpt;
	
	local int final_res_tr_id;
	local int final_res_cmp_id_base;
	local int final_res_err_n;
	
	local int final_res_tr_mcd = UVM_STDOUT;
	local int exp_res_tr_mcd = UVM_STDOUT;
	
	function void set_final_res_tr_mcd(int mcd);
		this.final_res_tr_mcd = mcd;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.final_res_port = new("final_res_port", this);
		
		this.final_res_mb = new();
		
		this.final_res_tr_id = 0;
		this.final_res_cmp_id_base = 0;
		this.final_res_err_n = 0;
		
		if(!uvm_config_db #(FmapCfg)::get(null, "", "fmap_cfg", this.fmap_cfg))
			`uvm_fatal(this.get_name(), "cannot get fmap_cfg!!!")
		if(!uvm_config_db #(PoolCalCfg)::get(null, "", "cal_cfg", this.cal_cfg))
			`uvm_fatal(this.get_name(), "cannot get cal_cfg!!!")
		
		if(!uvm_config_db #(PandaMemoryAdapter)::get(null, "", "fmap_mem", this.fmap_mem))
			`uvm_fatal(this.get_name(), "cannot get fmap_mem!!!")
		
		this.exp_res_tr_mcd = $fopen("exp_res_tr_log.txt");
		this.create_exp_res_adpt();
		this.gen_exp_final_res();
		`panda_print_with(this.exp_res_adpt, this.exp_res_tr_mcd, Util::get_object_printer())
		$fclose(this.exp_res_tr_mcd);
	endfunction
	
	virtual function void write_final_res(panda_axis_trans tr);
		AbstractFinalResAdapter adapter;
		
		adapter = this.create_final_res_adapter();
		
		if(adapter != null)
		begin
			adapter.id = this.final_res_tr_id;
			adapter.convert(tr);
			
			if(!this.final_res_mb.try_put(adapter))
				`uvm_error(this.get_name(), "cannot try_put final_res_mb")
			
			this.final_res_tr_id++;
		end
	endfunction
	
	task main_phase(uvm_phase phase);
		forever
		begin
			AbstractFinalResAdapter res_adapter;
			
			// 从信箱取最终结果
			this.final_res_mb.get(res_adapter);
			
			// 打印最终结果
			res_adapter.print_id_base = this.final_res_cmp_id_base;
			`panda_print_with(res_adapter, this.final_res_tr_mcd, Util::get_object_printer())
			
			// 比对最终结果的误差
			for(int i = 0;i < res_adapter.data_fifo.size();i++)
			begin
				ErrorValue err_v;
				
				err_v = res_adapter.data_fifo[i].cmp_err(this.exp_res_adpt.data_fifo[this.final_res_cmp_id_base + i]);
				err_v.id = this.final_res_cmp_id_base + i;
				
				if(err_v != null)
				begin
					if(!err_v.is_err_acceptable())
					begin
						`panda_print_with(err_v, this.final_res_tr_mcd, Util::get_object_printer())
						
						`uvm_warning(this.get_name(), $sformatf("err_v is not acceptable, id = %0d", this.final_res_cmp_id_base + i))
						
						this.final_res_err_n++;
					end
				end
			end
			
			`uvm_info(this.get_name(), $sformatf("check final result(from %0d to %0d)", this.final_res_cmp_id_base, this.final_res_cmp_id_base + res_adapter.data_fifo.size()), UVM_LOW)
			
			this.final_res_cmp_id_base += res_adapter.data_fifo.size();
		end
	endtask
	
	function void report_phase(uvm_phase phase);
		super.report_phase(phase);
		
		`uvm_info(this.get_name(), $sformatf("final_res_n = %0d", this.final_res_cmp_id_base), UVM_LOW)
		`uvm_info(this.get_name(), $sformatf("final_res_err_n = %0d", this.final_res_err_n), UVM_LOW)
	endfunction
	
	local function void gen_exp_final_res();
		Fmap fmap_this; // 特征图(对象)
		
		int unsigned cgrpn; // 总通道组数
		int unsigned ext_fmap_w; // 扩展特征图宽度
		int unsigned ext_fmap_h; // 扩展特征图高度
		int unsigned ofmap_w; // 输出特征图宽度
		int unsigned ofmap_h; // 输出特征图高度
		
		// 得到整个特征图
		if(!$cast(fmap_this, this.fmap_mem.data_blk))
		begin
			`uvm_error(this.get_name(), "cannot cast this.fmap_mem.data_blk -> fmap_this")
			
			return;
		end
		
		cgrpn = (this.fmap_cfg.fmap_c / this.cal_cfg.atomic_c) + ((this.fmap_cfg.fmap_c % this.cal_cfg.atomic_c) ? 1:0);
		ext_fmap_w = this.fmap_cfg.fmap_w + this.cal_cfg.external_padding_left + this.cal_cfg.external_padding_right;
		ext_fmap_h = this.fmap_cfg.fmap_h + this.cal_cfg.external_padding_top + this.cal_cfg.external_padding_bottom;
		
		ofmap_w = ((ext_fmap_w - this.cal_cfg.pool_window_w) / this.cal_cfg.pool_horizontal_stride) + 1;
		ofmap_h = ((ext_fmap_h - this.cal_cfg.pool_window_h) / this.cal_cfg.pool_vertical_stride) + 1;
		
		for(int unsigned cg = 0;cg < cgrpn;cg++)
		begin
			int unsigned cgrp_depth; // 通道组深度
			int pool_window_ext_y; // 池化窗口起始y坐标
			
			cgrp_depth = 
				((cg == (cgrpn - 1)) && (this.fmap_cfg.fmap_c % this.cal_cfg.atomic_c)) ? 
					(this.fmap_cfg.fmap_c % this.cal_cfg.atomic_c):
					this.cal_cfg.atomic_c;
			pool_window_ext_y = -int'(this.cal_cfg.external_padding_top);
			
			for(int unsigned oy = 0;oy < ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? ofmap_h:ext_fmap_h);oy++)
			begin
				for(int unsigned v_dup_i = 0;v_dup_i < ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? 1:this.cal_cfg.upsample_vertical_n);v_dup_i++)
				begin
					int pool_window_ext_x; // 池化窗口起始x坐标
					
					pool_window_ext_x = -int'(this.cal_cfg.external_padding_left);
					
					for(int unsigned ox = 0;ox < ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? ofmap_w:ext_fmap_w);ox++)
					begin
						AbstractData ofmap_sfc[];
						
						ofmap_sfc = new[cgrp_depth * ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? 1:this.cal_cfg.upsample_horizontal_n)];
						
						// 创建1个表面的数据
						foreach(ofmap_sfc[_i])
						begin
							ofmap_sfc[_i] = this.create_abst_data();
						end
						
						for(int unsigned py = 0;py < ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? this.cal_cfg.pool_window_h:1);py++)
						begin
							for(int unsigned px = 0;px < ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? this.cal_cfg.pool_window_w:this.cal_cfg.upsample_horizontal_n);px++)
							begin
								int pool_x; // 池化点x坐标
								int pool_y; // 池化点y坐标
								
								pool_x = pool_window_ext_x + ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? int'(px):0);
								pool_y = pool_window_ext_y + ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? int'(py):0);
								
								if(pool_x >= 0 && pool_x < this.fmap_cfg.fmap_w && pool_y >= 0 && pool_y < this.fmap_cfg.fmap_h)
								begin // 当前池化点不是填充点
									DataBlk fmap_data_blk; // 特征图数据块
									FmapSfc fmap_sfc; // 特征图表面
									int unsigned fmap_build_rid;
									int unsigned fmap_actual_rid;
									
									// 取出特征图表面行
									fmap_build_rid = cg * this.fmap_cfg.fmap_h + pool_y;
									fmap_actual_rid = fmap_this.rid_hash[fmap_build_rid];
									fmap_data_blk = fmap_this.get_sub_data_blk(fmap_actual_rid);
									
									if(fmap_data_blk == null)
									begin
										`uvm_error(this.get_name(), $sformatf("cannot get fmap_sfc_row(cg = %0d, y = %0d, actual_rid = %0d)", cg, pool_y, fmap_actual_rid))
										
										break;
									end
									
									// 取出特征图表面
									fmap_data_blk = fmap_data_blk.get_sub_data_blk(pool_x);
									
									if(fmap_data_blk == null)
									begin
										`uvm_error(this.get_name(), $sformatf("cannot get fmap_sfc(x = %0d)", pool_x))
										
										break;
									end
									
									if(!$cast(fmap_sfc, fmap_data_blk))
									begin
										`uvm_error(this.get_name(), "cannot cast fmap_data_blk -> fmap_sfc")
										
										break;
									end
									
									// 检查特征图表面深度
									if(fmap_sfc.get_size() != cgrp_depth)
									begin
										`uvm_error(this.get_name(), $sformatf("Expected fmap_sfc_depth is %0d, but it's %0d", cgrp_depth, fmap_sfc.get_size()))
										
										break;
									end
									
									if(this.cal_cfg.pool_mode == POOL_MODE_MAX)
									begin
										if((px == 0) && (py == 0))
										begin
											for(int unsigned d = 0;d < cgrp_depth;d++)
											begin
												ofmap_sfc[d].to_assign(fmap_sfc.data[d]); // ofmap_sfc[d] = fmap_sfc.data[d]
											end
										end
										else
										begin
											for(int unsigned d = 0;d < cgrp_depth;d++)
											begin
												if(fmap_sfc.data[d].is_greater_than(ofmap_sfc[d])) // fmap_sfc.data[d] > ofmap_sfc[d]
													ofmap_sfc[d].to_assign(fmap_sfc.data[d]); // ofmap_sfc[d] = fmap_sfc.data[d]
											end
										end
									end
									else if(this.cal_cfg.pool_mode == POOL_MODE_AVG)
									begin
										for(int unsigned d = 0;d < cgrp_depth;d++)
										begin
											ofmap_sfc[d].add_assign(fmap_sfc.data[d]); // ofmap_sfc[d] += fmap_sfc.data[d]
										end
									end
									else if(this.cal_cfg.pool_mode == POOL_MODE_UPSP)
									begin
										for(int unsigned d = 0;d < cgrp_depth;d++)
										begin
											ofmap_sfc[px * cgrp_depth + d].to_assign(fmap_sfc.data[d]); // ofmap_sfc[px * cgrp_depth + d] = fmap_sfc.data[d]
										end
									end
								end
								else
								begin
									if(this.cal_cfg.pool_mode == POOL_MODE_MAX)
									begin
										if((px == 0) && (py == 0))
										begin
											for(int unsigned d = 0;d < cgrp_depth;d++)
											begin
												ofmap_sfc[d].set_to_zero(); // ofmap_sfc[d] = 0
											end
										end
										else
										begin
											for(int unsigned d = 0;d < cgrp_depth;d++)
											begin
												if(this.create_abst_data().is_greater_than(ofmap_sfc[d])) // 0 > ofmap_sfc[d]
													ofmap_sfc[d].set_to_zero(); // ofmap_sfc[d] = 0
											end
										end
									end
									else if(this.cal_cfg.pool_mode == POOL_MODE_UPSP)
									begin
										for(int unsigned d = 0;d < cgrp_depth;d++)
										begin
											if(this.cal_cfg.non_zero_const_padding_mode)
												ofmap_sfc[px * cgrp_depth + d].set_by_int16(this.cal_cfg.const_to_fill); // ofmap_sfc[px * cgrp_depth + d] = 常量
											else
												ofmap_sfc[px * cgrp_depth + d].set_to_zero(); // ofmap_sfc[px * cgrp_depth + d] = 0
										end
									end
								end
							end
						end
						
						// 后乘加处理
						if(this.cal_cfg.enable_post_mac)
						begin
							AbstractData param_a;
							AbstractData param_b;
							
							param_a = create_abst_data();
							param_b = create_abst_data();
							
							if(!this.cal_cfg.post_mac_is_a_eq_1)
							begin
								param_a.set_by_int32(this.cal_cfg.post_mac_param_a);
								
								foreach(ofmap_sfc[_i])
								begin
									ofmap_sfc[_i].mul_assign(param_a);
								end
							end
							
							if(!this.cal_cfg.post_mac_is_b_eq_0)
							begin
								param_b.set_by_int32(this.cal_cfg.post_mac_param_b);
								
								foreach(ofmap_sfc[_i])
								begin
									ofmap_sfc[_i].add_assign(param_b);
								end
							end
						end
						
						// 添加输出表面数据
						this.exp_res_adpt.put_data(ofmap_sfc);
						
						// 添加打印信息
						if(this.cal_cfg.pool_mode != POOL_MODE_UPSP)
						begin
							for(int unsigned _i = 0;_i < cgrp_depth;_i++)
							begin
								this.exp_res_adpt.print_context.push_back($sformatf("oy%0d, ox%0d, sfc_i%0d", oy, ox, _i));
							end
						end
						else
						begin
							for(int unsigned _i = 0;_i < this.cal_cfg.upsample_horizontal_n;_i++)
							begin
								for(int unsigned _j = 0;_j < cgrp_depth;_j++)
								begin
									this.exp_res_adpt.print_context.push_back(
										$sformatf(
											"oy%0d, ox%0d, sfc_i%0d",
											oy * this.cal_cfg.upsample_vertical_n + v_dup_i,
											ox * this.cal_cfg.upsample_horizontal_n + _i,
											_j
										)
									);
								end
							end
						end
						
						pool_window_ext_x += ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? this.cal_cfg.pool_horizontal_stride:1);
					end
				end
				
				pool_window_ext_y += ((this.cal_cfg.pool_mode != POOL_MODE_UPSP) ? this.cal_cfg.pool_vertical_stride:1);
			end
		end
	endfunction
	
	local function AbstractFinalResAdapter create_final_res_adapter();
		if(this.cal_cfg.calfmt == CAL_FMT_FP16)
			return Fp16FinalResAdapter::type_id::create();
		else
		begin
			`uvm_error(this.get_name(), "calfmt not supported!")
			
			return null;
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
	
	`tue_component_default_constructor(FinalResScoreboard)
	`uvm_component_utils(FinalResScoreboard)
	
endclass

class DMAS2MMDataLenScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(ConvSts)
);
	
	uvm_analysis_imp_final_res #(panda_axis_trans, DMAS2MMDataLenScoreboard) final_res_port;
	uvm_analysis_imp_req #(panda_axis_trans, DMAS2MMDataLenScoreboard) req_port;
	
	bit to_upd_ofmap_mem = 1'b0;
	
	local mailbox #(panda_axis_trans) final_res_mb;
	local mailbox #(DMAS2MMReqTransAdapter) req_mb;
	
	local int req_tr_id;
	local int match_tr_n;
	local int mismatch_tr_n;
	int total_bytes_n;
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.final_res_port = new("final_res_port", this);
		this.req_port = new("req_port", this);
		
		this.final_res_mb = new();
		this.req_mb = new();
		
		this.req_tr_id = 0;
		this.match_tr_n = 0;
		this.mismatch_tr_n = 0;
		this.total_bytes_n = 0;
	endfunction
	
	virtual function void write_final_res(panda_axis_trans tr);
		if(!this.final_res_mb.try_put(tr))
			`uvm_error(this.get_name(), "cannot put final_res_tr")
	endfunction
	
	virtual function void write_req(panda_axis_trans tr);
		DMAS2MMReqTransAdapter req_adapter;
		
		req_adapter = DMAS2MMReqTransAdapter::type_id::create();
		req_adapter.convert(tr);
		req_adapter.tr_id = this.req_tr_id;
		
		if(!this.req_mb.try_put(req_adapter))
			`uvm_error(this.get_name(), "cannot put req_adapter")
		
		this.req_tr_id++;
	endfunction
	
	task main_phase(uvm_phase phase);
		forever
		begin
			DMAS2MMReqTransAdapter cmd_req;
			panda_axis_trans final_res_tr;
			
			this.req_mb.get(cmd_req);
			this.final_res_mb.get(final_res_tr);
			
			if(cmd_req.btt == final_res_tr.get_bytes_n())
			begin
				`uvm_info(this.get_name(), $sformatf("btt(%0d) match", cmd_req.btt), UVM_LOW)
				
				this.total_bytes_n += cmd_req.btt;
				
				if(this.to_upd_ofmap_mem)
				begin
					for(int i = 0;i < final_res_tr.get_len();i++)
					begin
						for(int j = 0;j < (final_res_tr.get_configuration().data_width / 8);j++)
						begin
							if(final_res_tr.keep[i][j])
							begin
								this.get_status().ofmap_mem.put(
									final_res_tr.data[i][8*j+:8], 1'b1, 1,
									cmd_req.baseaddr, i * (final_res_tr.get_configuration().data_width / 8) + j
								);
							end
						end
					end
				end
				
				this.match_tr_n++;
			end
			else
			begin
				`uvm_error(this.get_name(), $sformatf("btt(%0d) res_len(%0d) mismatch", cmd_req.btt, final_res_tr.get_bytes_n()))
				
				this.mismatch_tr_n++;
			end
		end
	endtask
	
	function void check_phase(uvm_phase phase);
		if(this.final_res_mb.num())
			`uvm_error(this.get_name(), "final_res_mb is not empty")
		else
			`uvm_info(this.get_name(), "final_res_mb is empty", UVM_LOW)
		
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
	
	`tue_component_default_constructor(DMAS2MMDataLenScoreboard)
	`uvm_component_utils(DMAS2MMDataLenScoreboard)
	
endclass

`endif
