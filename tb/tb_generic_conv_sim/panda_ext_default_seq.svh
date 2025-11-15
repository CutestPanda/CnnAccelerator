`ifndef __PANDA_EXT_DEFAULT_SEQ_H

`define __PANDA_EXT_DEFAULT_SEQ_H

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
		
		if(!uvm_config_db #(PandaMemoryAdapter)::get(null, "", MEM_NAME, this.mem))
			`uvm_fatal(this.get_name(), $sformatf("cannot get %s!!!", MEM_NAME))
	endtask
	
	task body();
		int dma_strm_axis_byte_width;
		panda_axis_trans dma_cmd_axis_req;
		panda_axis_slave_trans send_dma_cmd_axis_tr;
		panda_axis_slave_trans recv_dma_cmd_axis_tr;
		panda_axis_master_trans dma_strm_axis_tr;
		
		dma_strm_axis_byte_width = this.p_sequencer.dma_strm_axis_sqr.get_configuration().data_width / 8;
		
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
				
				dma_strm_axis_tr.len = (btt / dma_strm_axis_byte_width) + ((btt % dma_strm_axis_byte_width) ? 1:0);
				dma_strm_axis_tr.data = new[dma_strm_axis_tr.len];
				dma_strm_axis_tr.keep = new[dma_strm_axis_tr.len];
				
				for(int i = 0;i < dma_strm_axis_tr.len;i++)
				begin
					dma_strm_axis_tr.keep[i] = 
						((i == (dma_strm_axis_tr.len - 1)) && (btt % dma_strm_axis_byte_width)) ? 
							((1 << (btt % dma_strm_axis_byte_width)) - 1):
							((1 << dma_strm_axis_byte_width) - 1);
					
					for(int j = 0;j < dma_strm_axis_byte_width / 2;j++)
						dma_strm_axis_tr.data[i][16*j+:16] = this.mem.get(2, baseaddr, i * (dma_strm_axis_byte_width / 2) + j);
				end
				
				`uvm_send(dma_strm_axis_tr)
			end
		join
	endtask
	
	`uvm_object_param_utils(DmaStrmAxisVseq #(.MEM_NAME(MEM_NAME)))
	
endclass

class ReqGenBlkCtrlDefaultSeq extends tue_sequence #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	rand bit is_zero_delay = 1'b0;
	
	function new(string name = "ReqGenBlkCtrlDefaultSeq");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task body();
		panda_blk_ctrl_dummy_trans tr;
		
		`uvm_do_with(tr, {
			if(is_zero_delay){
				process_start_delay == 0;
			}
		})
	endtask
	
	`uvm_object_utils(ReqGenBlkCtrlDefaultSeq)
	
endclass

`endif
