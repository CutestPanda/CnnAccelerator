`ifndef __PANDA_SAMPLE_SEQUENCE_H
`define __PANDA_SAMPLE_SEQUENCE_H

class panda_icb_master_default_sequence extends tue_sequence #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.REQ(panda_icb_master_trans),
	.RSP(panda_icb_master_trans),
	.PROXY_CONFIGURATION(panda_icb_configuration),
	.PROXY_STATUS(panda_icb_status)
);
	
	function new(string name = "panda_icb_master_default_sequence");
		super.new(name);
		
		this.set_automatic_phase_objection(0);
    endfunction
	
	task body();
		// blank
    endtask
	
	`uvm_object_utils(panda_icb_master_default_sequence)
	
endclass

class panda_icb_slave_default_sequence extends tue_reactive_sequence #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.ITEM(panda_icb_slave_trans),
	.RSP(panda_icb_slave_trans),
	.REQUEST(panda_icb_trans),
	.PROXY_CONFIGURATION(panda_icb_configuration),
	.PROXY_STATUS(panda_icb_status)
);
	
	function new(string name = "panda_icb_slave_default_sequence");
		super.new(name);
		
		this.set_automatic_phase_objection(0);
    endfunction
	
	task body();
		panda_icb_trans request;
		panda_icb_slave_trans tr;
		panda_icb_status sts;
		panda_icb_configuration cfg;
		
		forever
		begin
			this.get_request(request);
			
			`uvm_create(tr)
			
			tr.access_type = request.access_type;
			
			if(request.is_write())
			begin
				void'(tr.randomize() with {});
			end
			else
			begin
				panda_icb_data rdata;
				
				sts = request.get_status();
				cfg = request.get_configuration();
				rdata = sts.memory.get(cfg.data_width / 8, request.addr, 0);
				
				void'(tr.randomize() with {
					data == rdata;
				});
			end
			
			`uvm_send(tr)
		end
    endtask
	
	`uvm_object_utils(panda_icb_slave_default_sequence)
	
endclass

class panda_axis_master_default_sequence extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(panda_axis_master_trans),
	.RSP(panda_axis_master_trans),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "panda_axis_master_default_sequence");
		super.new(name);
		
		this.set_automatic_phase_objection(0);
    endfunction
	
	task body();
		// blank
    endtask
	
	`uvm_object_utils(panda_axis_master_default_sequence)
	
endclass

class panda_axis_slave_default_sequence extends tue_reactive_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.ITEM(panda_axis_slave_trans),
	.RSP(panda_axis_slave_trans),
	.REQUEST(panda_axis_trans),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "panda_axis_slave_default_sequence");
		super.new(name);
		
		this.set_automatic_phase_objection(0);
    endfunction
	
	task body();
		panda_axis_trans request;
		panda_axis_slave_trans tr;
		
		forever
		begin
			this.get_request(request);
			
			`uvm_do_with(tr, {})
		end
    endtask
	
	`uvm_object_utils(panda_axis_slave_default_sequence)
	
endclass

`endif
