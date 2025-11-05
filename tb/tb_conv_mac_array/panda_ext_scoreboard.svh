`ifndef __PANDA_EXT_SCOREBOARD_H

`define __PANDA_EXT_SCOREBOARD_H

`uvm_analysis_imp_decl(_array_i_ftm)
`uvm_analysis_imp_decl(_array_i_kernal)
`uvm_analysis_imp_decl(_array_o)

class ConvMacArrayScoreboard extends tue_scoreboard #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	calfmt_t cal_fmt = FP16;
	int atomic_c = 4;
	int atomic_k = 4;
	int cal_round_n = 2;
	
	uvm_analysis_imp_array_i_ftm #(panda_axis_trans, ConvMacArrayScoreboard) array_i_ftm_port;
	uvm_analysis_imp_array_i_kernal #(panda_axis_trans, ConvMacArrayScoreboard) array_i_kernal_port;
	uvm_analysis_imp_array_o #(panda_axis_trans, ConvMacArrayScoreboard) array_o_port;
	
	local SfcStrmAdapter ftm_sfc_strm_fifo[$];
	local SfcStrmAdapter kernal_sfc_strm_fifo[$];
	
	local AbstractSurface expect_fifo[$];
	local AbstractSurface res_fifo[$];
	
	local int chk_i;
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.array_i_ftm_port = new("array_i_ftm_port", this);
		this.array_i_kernal_port = new("array_i_kernal_port", this);
		this.array_o_port = new("array_o_port", this);
		
		this.chk_i = 0;
	endfunction
	
	virtual function void write_array_i_ftm(panda_axis_trans tr);
		SfcStrmAdapter adapter;
		
		adapter = new();
		adapter.convert(tr, cal_fmt, atomic_c);
		
		this.ftm_sfc_strm_fifo.push_back(adapter);
	endfunction
	
	virtual function void write_array_i_kernal(panda_axis_trans tr);
		SfcStrmAdapter adapter;
		
		adapter = new();
		adapter.convert(tr, cal_fmt, atomic_c);
		
		this.kernal_sfc_strm_fifo.push_back(adapter);
	endfunction
	
	virtual function void write_array_o(panda_axis_trans tr);
		if(tr.len == 1)
		begin
			AbstractSurface res;
			
			res = convert_array_out(tr);
			
			res_fifo.push_back(res);
		end
		else
			`uvm_error(this.get_name(), "array_o tr len != 1")
	endfunction
	
	task main_phase(uvm_phase phase);
		fork
			forever
			begin
				AbstractSurface res;
				AbstractSurface exp;
				uvm_object err_v;
				bit err_flag;
				
				wait((this.res_fifo.size() > 0) && (this.expect_fifo.size() > 0));
				
				res = this.res_fifo.pop_front();
				exp = this.expect_fifo.pop_front();
				
				err_v = exp.cmp_err(res, err_flag);
				
				`uvm_info(this.get_name(), $sformatf("chk_i = %0d", this.chk_i), UVM_LOW)
				err_v.print();
				
				if(err_flag)
				begin
					res.print();
					exp.print();
				end
				
				this.chk_i++;
			end
			
			forever
			begin
				SfcStrmAdapter ftm_sfc_strm;
				SfcStrmAdapter kernal_sfc_strm;
				
				wait((this.ftm_sfc_strm_fifo.size() > 0) && (this.kernal_sfc_strm_fifo.size() > 0));
				
				ftm_sfc_strm = this.ftm_sfc_strm_fifo.pop_front();
				kernal_sfc_strm = this.kernal_sfc_strm_fifo.pop_front();
				
				for(int m = 0;m < ftm_sfc_strm.get_len();m++)
				begin
					AbstractSurface ftm_sfc;
					
					ftm_sfc = ftm_sfc_strm.sfc_arr[m];
					
					for(int i = 0;i < this.cal_round_n;i++)
					begin
						AbstractSurface res_sfc;
						AbstractSurface kernal_sfc_group[];
						
						kernal_sfc_group = new[this.atomic_k];
						
						for(int k = 0;k < this.atomic_k;k++)
						begin
							if((i * this.atomic_k + k) < kernal_sfc_strm.get_len())
							begin
								AbstractSurface kernal_sfc;
								
								kernal_sfc = kernal_sfc_strm.sfc_arr[i * this.atomic_k + k];
								kernal_sfc_group[k] = kernal_sfc;
							end
							else
								kernal_sfc_group[k] = null;
						end
						
						res_sfc = gen_mul_add_res(ftm_sfc, kernal_sfc_group);
						
						this.expect_fifo.push_back(res_sfc);
					end
				end
			end
		join
	endtask
	
	local function AbstractSurface gen_mul_add_res(AbstractSurface ftm_sfc, ref AbstractSurface kernal_sfc_group[]);
		AbstractSurface res;
		
		if(this.cal_fmt == FP16)
			res = Fp16Surface::type_id::create("ref_fp16_sfc");
		else if(this.cal_fmt == INT16)
			res = Int16Surface::type_id::create("ref_int16_sfc");
		else
			`uvm_fatal(this.get_name(), "func gen_mul_add_res cal_fmt not supported!")
		
		res.len = kernal_sfc_group.size();
		res.org_data = new[kernal_sfc_group.size()];
		
		for(int i = 0;i < kernal_sfc_group.size();i++)
		begin
			if(this.cal_fmt == FP16)
				res.org_data[i] = PackedReal::type_id::create();
			else
				`uvm_fatal(this.get_name(), "func gen_mul_add_res cal_fmt not supported!")
			
			if(kernal_sfc_group[i] == null)
				res.org_data[i].set_to_zero();
			else
				res.org_data[i] = ftm_sfc.mul_add(kernal_sfc_group[i]);
		end
		
		return res;
	endfunction
	
	local function AbstractSurface convert_array_out(panda_axis_trans tr);
		AbstractSurface res;
		
		if(this.cal_fmt == FP16)
		begin
			res = Fp16Surface::type_id::create("res_fp16_sfc");
			res.len = this.atomic_k;
			res.org_data = new[this.atomic_k];
			
			for(int i = 0;i < this.atomic_k;i++)
			begin
				bit[47:0] now_res;
				int exp;
				longint frac;
				PackedReal packed_real;
				
				now_res = tr.data[0][48*i+:48];
				exp = {24'd0, now_res[47:40]};
				frac = {{24{now_res[39]}}, now_res[39:0]};
				
				packed_real = PackedReal::type_id::create();
				packed_real.data = real'(frac) * (2.0 ** (exp - 50));
				res.org_data[i] = packed_real;
			end
		end
		else
			`uvm_fatal(this.get_name(), "func convert_array_out cal_fmt not supported!")
		
		return res;
	endfunction
	
	`tue_component_default_constructor(ConvMacArrayScoreboard)
	`uvm_component_utils(ConvMacArrayScoreboard)
	
endclass

`endif
