`ifndef __PANDA_CONFIGURATION_H
`define __PANDA_CONFIGURATION_H

class panda_delay_configuration extends tue_configuration;
	
	rand int min_delay;
	rand int mid_delay[2];
	rand int max_delay;
	
	rand int weight_zero_delay;
	rand int weight_short_delay;
	rand int weight_long_delay;
	
	constraint c_valid_min_max_delay{
		min_delay >= 0;
		max_delay >= 0;
		max_delay >= min_delay;
	}
	
	constraint c_valid_mid_delay{
		solve min_delay, max_delay before mid_delay;
		
		mid_delay[0] >= min_delay;
		mid_delay[1] <= max_delay;
		mid_delay[0] <= mid_delay[1];
		
		if((max_delay - min_delay) >= 1){
			if(min_delay == 0){
				mid_delay[0] >= 1;
			}
		}
	}
	
	constraint c_valid_weight{
		solve min_delay before weight_zero_delay;
		
		if(min_delay > 0){
			weight_zero_delay == 0;
			
			(weight_short_delay > 0) || (weight_long_delay > 0);
		}else{
			weight_zero_delay >= 0;
			
			(weight_zero_delay > 0) || (weight_short_delay > 0) || (weight_long_delay > 0);
		}
		
		weight_short_delay >= 0;
		weight_long_delay >= 0;
	}
	
	`tue_object_default_constructor(panda_delay_configuration)
	
	`uvm_object_utils_begin(panda_delay_configuration)
		`uvm_field_int(min_delay, UVM_DEFAULT | UVM_DEC)
		`uvm_field_sarray_int(mid_delay, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(max_delay, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(weight_zero_delay, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(weight_short_delay, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(weight_long_delay, UVM_DEFAULT | UVM_DEC)
	`uvm_object_utils_end
	
endclass

virtual class panda_trans_factory extends uvm_object;
	
	pure virtual function uvm_sequence_item create_item();
	
	`tue_object_default_constructor(panda_trans_factory)
	
endclass

class panda_icb_configuration extends tue_configuration;
	
	panda_icb_vif vif;
	
	rand int address_width;
	rand int data_width;
	rand int strobe_width;
	
	rand int outstanding_n;
	
	rand int response_weight_okay;
	rand int response_weight_error;
	
	rand panda_delay_configuration req_delay;
	rand panda_delay_configuration rsp_delay;
	rand panda_delay_configuration cmd_ready_delay;
	rand panda_delay_configuration rsp_ready_delay;
	
	rand bit default_cmd_ready;
	rand bit default_rsp_ready;
	
	constraint c_valid_addr_width{
		address_width inside {[1:`PANDA_ICB_MAX_ADDR_WIDTH]};
	}
	
	constraint c_valid_data_width{
		data_width inside {8, 16, 32, 64, 128, 256, 512, 1024};
		data_width <= `PANDA_ICB_MAX_DATA_WIDTH;
	}
	
	constraint c_valid_strobe_width{
		solve data_width before strobe_width;
		
		strobe_width == (data_width / 8);
	}
	
	constraint c_valid_outstanding_n{
		outstanding_n >= 1;
	}
	
	constraint c_valid_response_weight{
		response_weight_okay >= 0;
		response_weight_error >= 0;
	}
	
	function new(string name = "panda_icb_configuration");
		super.new(name);
		
		this.req_delay = panda_delay_configuration::type_id::create("req_delay");
		this.rsp_delay = panda_delay_configuration::type_id::create("rsp_delay");
		this.cmd_ready_delay = panda_delay_configuration::type_id::create("cmd_ready_delay");
		this.rsp_ready_delay = panda_delay_configuration::type_id::create("rsp_ready_delay");
	endfunction
	
	function void post_randomize();
		super.post_randomize();
		
		this.response_weight_okay = (this.response_weight_okay >= 1) ? this.response_weight_okay:1;
	endfunction
	
	`uvm_object_utils_begin(panda_icb_configuration)
		`uvm_field_int(address_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(data_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(strobe_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(outstanding_n, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(response_weight_okay, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(response_weight_error, UVM_DEFAULT | UVM_DEC)
		`uvm_field_object(req_delay, UVM_DEFAULT)
		`uvm_field_object(rsp_delay, UVM_DEFAULT)
		`uvm_field_object(cmd_ready_delay, UVM_DEFAULT)
		`uvm_field_object(rsp_ready_delay, UVM_DEFAULT)
		`uvm_field_int(default_cmd_ready, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(default_rsp_ready, UVM_DEFAULT | UVM_BIN)
	`uvm_object_utils_end
	
endclass

class panda_axis_configuration extends tue_configuration;
	
	panda_axis_vif vif;
	
	rand int data_width;
	rand int mask_width;
	rand int user_width;
	
	rand panda_delay_configuration valid_delay;
	rand panda_delay_configuration ready_delay;
	
	rand bit default_ready;
	rand bit has_keep;
	rand bit has_strb;
	rand bit has_last;
	
	constraint c_valid_data_width{
		(data_width % 8) == 0;
		data_width <= `PANDA_AXIS_MAX_DATA_WIDTH;
	}
	
	constraint c_valid_mask_width{
		solve data_width before mask_width;
		
		mask_width == (data_width / 8);
	}
	
	constraint c_valid_user_width{
		user_width >= 0;
	}
	
	function new(string name = "panda_axis_configuration");
		super.new(name);
		
		this.valid_delay = panda_delay_configuration::type_id::create("valid_delay");
		this.ready_delay = panda_delay_configuration::type_id::create("ready_delay");
	endfunction
	
	`uvm_object_utils_begin(panda_axis_configuration)
		`uvm_field_int(data_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(mask_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_int(user_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_object(valid_delay, UVM_DEFAULT)
		`uvm_field_object(ready_delay, UVM_DEFAULT)
		`uvm_field_int(default_ready, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(has_keep, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(has_strb, UVM_DEFAULT | UVM_BIN)
		`uvm_field_int(has_last, UVM_DEFAULT | UVM_BIN)
	`uvm_object_utils_end
	
endclass

class panda_blk_ctrl_configuration extends tue_configuration;
	
	panda_blk_ctrl_vif vif;
	panda_trans_factory tr_factory;
	bit complete_monitor_mode = 1'b1;
	
	rand int params_width;
	
	rand panda_delay_configuration start_delay;
	
	constraint c_valid_params_width{
		params_width inside {[0:`PANDA_BLK_CTRL_MAX_PARAMS_WIDTH]};
	}
	
	function new(string name = "panda_blk_ctrl_configuration");
		super.new(name);
		
		this.start_delay = panda_delay_configuration::type_id::create("start_delay");
	endfunction
	
	`uvm_object_utils_begin(panda_blk_ctrl_configuration)
		`uvm_field_int(params_width, UVM_DEFAULT | UVM_DEC)
		`uvm_field_object(start_delay, UVM_DEFAULT)
	`uvm_object_utils_end
	
endclass

`endif
