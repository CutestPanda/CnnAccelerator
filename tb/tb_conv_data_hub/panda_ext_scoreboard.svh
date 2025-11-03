`ifndef __PANDA_EXT_SCOREBOARD_H

`define __PANDA_EXT_SCOREBOARD_H

`include "panda_defines.svh"

`uvm_analysis_imp_decl(_rd_req)
`uvm_analysis_imp_decl(_fout)

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
		
		rd_req_tr = new(tr);
		rd_req_tr.id = this.rd_req_tr_id;
		`panda_print(rd_req_tr, this.rd_req_tr_mcd)
		
		if(rd_req_tr.to_rst_buf)
			`uvm_info(this.get_name(), "get rst_buf", UVM_LOW)
		else
			this.rd_req_tr_fifo.push_back(rd_req_tr);
		
		this.rd_req_tr_id++;
	endfunction
	
	virtual function void write_fout(panda_axis_trans tr);
		this.fout_tr_fifo.push_back(tr);
	endfunction
	
	protected function void check_fout(panda_axis_trans res_tr, panda_axis_trans ref_tr);
		if(res_tr.compare(ref_tr))
		begin
			`uvm_info(this.get_name(), $sformatf("[%0d]match", this.chk_id), UVM_LOW)
			
			this.success_cnt++;
		end
		else
		begin
			`uvm_error(this.get_name(), $sformatf("[%0d]mismatch", this.chk_id))
			
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
			
			data_blk = this.mem.data_blk.get_sub_data_blk(fm_rd_req_tr.actual_sfc_rid);
			
			if(data_blk == null)
			begin
				`uvm_error(this.get_name(), $sformatf("cannot get fmap_row(actual_sfc_rid = %0d)!", fm_rd_req_tr.actual_sfc_rid))
				
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
				
				exp_fmap_fout.data[i] = {(`PANDA_AXIS_MAX_DATA_WIDTH){1'b0}};
				
				for(int unsigned j = 0;j < fm_rd_req_tr.vld_data_n_foreach_sfc;j++)
					exp_fmap_fout.data[i][16*j+:16] = fmap_sfc.get_pt_by_index(j);
			end
			
			if(sfc_err)
				continue;
			
			this.check_fout(fmap_fout_tr, exp_fmap_fout);
			
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
		
		rd_req_tr = new(tr);
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
		
		`panda_print(rd_req_tr, this.rd_req_tr_mcd)
		
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
				
				exp_kernal_fout.data[i] = {(`PANDA_AXIS_MAX_DATA_WIDTH){1'b0}};
				
				for(int unsigned j = 0;j < kernal_rd_req_tr.vld_data_n_foreach_sfc;j++)
					exp_kernal_fout.data[i][16*j+:16] = sfc_this.get_pt_by_index(j);
			end
			
			if(sfc_err)
			begin
				`uvm_error(this.get_name(), $sformatf("cannot get kernal_sfc(start = %0d, len = %0d)!", kernal_rd_req_tr.start_sfc_id, kernal_rd_req_tr.sfc_n_to_rd))
				
				continue;
			end
			
			this.check_fout(kernal_fout_tr, exp_kernal_fout);
			
			this.chk_id++;
		end
	endtask
	
	`tue_component_default_constructor(KernalBufScoreboard)
	`uvm_component_utils(KernalBufScoreboard)
	
endclass

`endif
