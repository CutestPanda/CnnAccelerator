`ifndef __PANDA_ICB_TRANSACTION_H
`define __PANDA_ICB_TRANSACTION_H

class panda_icb_trans extends tue_sequence_item #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.PROXY_CONFIGURATION(panda_icb_configuration),
	.PROXY_STATUS(panda_icb_status)
);
	
	rand panda_icb_access_type access_type;
	rand panda_icb_address addr;
	rand panda_icb_data data;
	rand panda_icb_strobe strobe;
	rand panda_icb_response_type response;
	
	rand int request_valid_delay;
	rand int response_ready_delay;
	rand int request_ready_delay;
	rand int response_valid_delay;
	
	uvm_event request_begin_event;
    time request_begin_time;
	uvm_event request_end_event;
    time request_end_time;
	uvm_event response_begin_event;
    time response_begin_time;
	uvm_event response_end_event;
    time response_end_time;
	
	function new(string name = "panda_icb_trans");
		super.new(name);
		
		this.access_type = PANDA_ICB_ACCESS_TYPE_NOT_SET;
		
		this.request_begin_event = this.get_event("request_begin");
		this.request_end_event = this.get_event("request_end");
		this.response_begin_event = this.get_event("response_begin");
		this.response_end_event = this.get_event("response_end");
	endfunction
	
	function bit is_write();
		return (this.access_type == PANDA_ICB_WRITE_ACCESS) ? 1'b1:1'b0;
	endfunction
	
	function bit is_read();
		return (this.access_type == PANDA_ICB_READ_ACCESS) ? 1'b1:1'b0;
	endfunction
	
	virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
		panda_icb_trans rhs_;
		do_compare = super.do_compare(rhs, comparer);
		
		if(!$cast(rhs_, rhs))
			`uvm_fatal(this.get_name(), "cmp cast err!")
		
		do_compare &= comparer.compare_field("addr", this.addr, rhs_.addr, this.configuration.address_width);
		do_compare &= comparer.compare_field("data", this.data, rhs_.data, this.configuration.data_width);
		do_compare &= comparer.compare_field("strobe", this.strobe, rhs_.strobe, this.configuration.strobe_width);
	endfunction
	
	`panda_declare_begin_end_event_api(request)
	`panda_declare_begin_end_event_api(response)
	
	constraint c_valid_address{
		(addr >> this.configuration.address_width) == 0;
	}
	
	constraint c_valid_data{
		(data >> this.configuration.data_width) == 0;
	}
	
	constraint c_valid_strobe{
		(strobe >> this.configuration.strobe_width) == 0;
	}
	
	constraint c_request_valid_delay{
		`panda_delay_constraint(request_valid_delay, this.configuration.req_delay)
	}
	
	constraint c_response_ready_delay{
		`panda_delay_constraint(response_ready_delay, this.configuration.rsp_ready_delay)
	}
	
	constraint c_request_ready_delay{
		`panda_delay_constraint(request_ready_delay, this.configuration.cmd_ready_delay)
	}
	
	constraint c_response_valid_delay{
		`panda_delay_constraint(response_valid_delay, this.configuration.rsp_delay)
	}
	
	constraint c_valid_response{
		response dist{
			PANDA_ICB_RSP_OK:=this.configuration.response_weight_okay,
			PANDA_ICB_RSP_ERR:=this.configuration.response_weight_error
		};
	}
	
	`uvm_object_utils_begin(panda_icb_trans)
		`uvm_field_enum(panda_icb_access_type, access_type, UVM_DEFAULT)
		`uvm_field_int(addr, UVM_DEFAULT | UVM_HEX | UVM_NOCOMPARE)
		`uvm_field_int(data, UVM_DEFAULT | UVM_HEX | UVM_NOCOMPARE)
		`uvm_field_int(strobe, UVM_DEFAULT | UVM_BIN | UVM_NOCOMPARE)
		`uvm_field_enum(panda_icb_response_type, response, UVM_DEFAULT)
		`uvm_field_int(request_valid_delay, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(response_ready_delay, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(request_ready_delay, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(response_valid_delay, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(request_begin_time, UVM_DEFAULT | UVM_TIME | UVM_NOCOMPARE)
		`uvm_field_int(request_end_time, UVM_DEFAULT | UVM_TIME | UVM_NOCOMPARE)
		`uvm_field_int(response_begin_time, UVM_DEFAULT | UVM_TIME | UVM_NOCOMPARE)
		`uvm_field_int(response_end_time, UVM_DEFAULT | UVM_TIME | UVM_NOCOMPARE)
	`uvm_object_utils_end
	
endclass

class panda_icb_master_trans extends panda_icb_trans;
	
	function void pre_randomize();
		super.pre_randomize();
		
		response.rand_mode(0);
		request_ready_delay.rand_mode(0);
		response_valid_delay.rand_mode(0);
		
		c_request_ready_delay.constraint_mode(0);
		c_response_valid_delay.constraint_mode(0);
		c_valid_response.constraint_mode(0);
	endfunction
	
	`tue_object_default_constructor(panda_icb_master_trans)
	`uvm_object_utils(panda_icb_master_trans)
	
endclass

class panda_icb_slave_trans extends panda_icb_trans;
	
	function void pre_randomize();
		super.pre_randomize();
		
		if(access_type == PANDA_ICB_ACCESS_TYPE_NOT_SET)
			`uvm_fatal("panda_icb_slave_trans", "Cannot rand: access_type not set!")
		
		access_type.rand_mode(0);
		addr.rand_mode(0);
		data.rand_mode(is_read() ? 1:0);
		strobe.rand_mode(0);
		request_valid_delay.rand_mode(0);
		response_ready_delay.rand_mode(0);
		
		c_valid_address.constraint_mode(0);
		c_valid_data.constraint_mode(is_read() ? 1:0);
		c_valid_strobe.constraint_mode(0);
		c_request_valid_delay.constraint_mode(0);
		c_response_ready_delay.constraint_mode(0);
	endfunction
	
	`tue_object_default_constructor(panda_icb_slave_trans)
	`uvm_object_utils(panda_icb_slave_trans)
	
endclass

class panda_axis_trans extends tue_sequence_item #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	rand int len;
	
	rand panda_axis_data data[];
	rand panda_axis_mask keep[];
	rand panda_axis_mask strb[];
	rand panda_axis_user user[];
	
	rand int stream_valid_delay[];
	rand int stream_ready_delay[];
	
	uvm_event stream_begin_event;
    time stream_begin_time;
	uvm_event stream_end_event;
    time stream_end_time;
	
	function new(string name = "panda_axis_trans");
		super.new(name);
		
		this.stream_begin_event = this.get_event("stream_begin");
		this.stream_end_event = this.get_event("stream_end");
	endfunction
	
	function int get_len();
		return this.len;
	endfunction
	
	function void init_req(panda_axis_data data, panda_axis_mask keep, panda_axis_mask strb, panda_axis_user user);
		this.len = 1;
		
		this.data = new[1];
		this.data[0] = data;
		
		if(this.configuration.has_keep)
		begin
			this.keep = new[1];
			this.keep[0] = keep;
		end
		
		if(this.configuration.has_strb)
		begin
			this.strb = new[1];
			this.strb[0] = strb;
		end
		
		if(this.configuration.user_width > 0)
		begin
			this.user = new[1];
			this.user[0] = user;
		end
	endfunction
	
	virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
		panda_axis_trans rhs_;
		do_compare = super.do_compare(rhs, comparer);
		
		if(!$cast(rhs_, rhs))
			`uvm_fatal(this.get_name(), "cmp cast err!")
		
		for(int i = 0;i < this.len;i++)
		begin
			do_compare &= comparer.compare_field("data", this.data[i], rhs_.data[i], this.configuration.data_width);
			
			if(this.configuration.has_keep)
				do_compare &= comparer.compare_field("keep", this.keep[i], rhs_.keep[i], this.configuration.data_width / 8);
			
			if(this.configuration.has_strb)
				do_compare &= comparer.compare_field("strb", this.strb[i], rhs_.strb[i], this.configuration.data_width / 8);
			
			if(this.configuration.user_width > 0)
				do_compare &= comparer.compare_field("user", this.user[i], rhs_.user[i], this.configuration.user_width);
		end
	endfunction
	
	`panda_put_fifo_to_dyn_arr(panda_axis_data, data)
	`panda_put_fifo_to_dyn_arr(panda_axis_mask, keep)
	`panda_put_fifo_to_dyn_arr(panda_axis_mask, strb)
	`panda_put_fifo_to_dyn_arr(panda_axis_user, user)
	
	`panda_get_element_from_dyn_arr(panda_axis_data, data)
	`panda_get_element_from_dyn_arr(panda_axis_mask, keep)
	`panda_get_element_from_dyn_arr(panda_axis_mask, strb)
	`panda_get_element_from_dyn_arr(panda_axis_user, user)
	`panda_get_element_from_dyn_arr(int, stream_valid_delay)
	`panda_get_element_from_dyn_arr(int, stream_ready_delay)
	
	`panda_declare_begin_end_event_api(stream)
	
	constraint c_single_len_stream{
		if(this.configuration.has_last)
			len >= 1;
		else
			len == 1;
	}
	
	constraint c_valid_data{
		solve len before data;
		
		data.size() == len;
		
		foreach(data[i]){
			(data[i] >> this.configuration.data_width) == 0;
		}
	}
	
	constraint c_valid_keep{
		solve len before keep;
		
		if(this.configuration.has_keep)
			keep.size() == len;
		else
			keep.size() == 0;
		
		foreach(keep[i]){
			(keep[i] >> this.configuration.mask_width) == 0;
		}
	}
	
	constraint c_valid_strb{
		solve len before strb;
		
		if(this.configuration.has_strb)
			strb.size() == len;
		else
			strb.size() == 0;
		
		foreach(strb[i]){
			(strb[i] >> this.configuration.mask_width) == 0;
		}
	}
	
	constraint c_valid_user{
		solve len before user;
		
		if(this.configuration.user_width > 0)
			user.size() == len;
		else
			user.size() == 0;
		
		foreach(user[i]){
			(user[i] >> this.configuration.user_width) == 0;
		}
	}
	
	constraint c_stream_valid_delay{
		solve len before stream_valid_delay;
		
		stream_valid_delay.size() == len;
		
		`panda_array_delay_constraint(stream_valid_delay, this.configuration.valid_delay)
	}
	
	constraint c_stream_ready_delay{
		solve len before stream_ready_delay;
		
		stream_ready_delay.size() == len;
		
		`panda_array_delay_constraint(stream_ready_delay, this.configuration.ready_delay)
	}
	
	`uvm_object_utils_begin(panda_axis_trans)
		`uvm_field_int(len, UVM_DEFAULT | UVM_DEC)
		`uvm_field_array_int(data, UVM_DEFAULT | UVM_HEX | UVM_NOCOMPARE)
		`uvm_field_array_int(keep, UVM_DEFAULT | UVM_BIN | UVM_NOCOMPARE)
		`uvm_field_array_int(strb, UVM_DEFAULT | UVM_BIN | UVM_NOCOMPARE)
		`uvm_field_array_int(user, UVM_DEFAULT | UVM_HEX | UVM_NOCOMPARE)
		`uvm_field_array_int(stream_valid_delay, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_array_int(stream_ready_delay, UVM_DEFAULT | UVM_DEC | UVM_NOCOMPARE)
		`uvm_field_int(stream_begin_time, UVM_DEFAULT | UVM_TIME | UVM_NOCOMPARE)
		`uvm_field_int(stream_end_time, UVM_DEFAULT | UVM_TIME | UVM_NOCOMPARE)
	`uvm_object_utils_end
	
endclass

class panda_axis_master_trans extends panda_axis_trans;
	
	function void pre_randomize();
		super.pre_randomize();
		
		stream_ready_delay.rand_mode(0);
		
		c_stream_ready_delay.constraint_mode(0);
	endfunction
	
	`tue_object_default_constructor(panda_axis_master_trans)
	`uvm_object_utils(panda_axis_master_trans)
	
endclass

class panda_axis_slave_trans extends panda_axis_trans;
	
	function void pre_randomize();
		super.pre_randomize();
		
		data.rand_mode(0);
		keep.rand_mode(0);
		strb.rand_mode(0);
		user.rand_mode(0);
		stream_valid_delay.rand_mode(0);
		
		c_single_len_stream.constraint_mode(0);
		c_valid_data.constraint_mode(0);
		c_valid_keep.constraint_mode(0);
		c_valid_strb.constraint_mode(0);
		c_valid_user.constraint_mode(0);
		c_stream_valid_delay.constraint_mode(0);
	endfunction
	
	function int get_ready_delay();
		if(this.stream_ready_delay.size() > 0)
			return this.stream_ready_delay[0];
		else
			return 0;
	endfunction
	
	constraint c_slave_single_len{
		len == 1;
	}
	
	`tue_object_default_constructor(panda_axis_slave_trans)
	`uvm_object_utils(panda_axis_slave_trans)
	
endclass

virtual class panda_blk_ctrl_abstract_trans extends tue_sequence_item #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(panda_blk_ctrl_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	rand int process_start_delay;
	
	uvm_event process_begin_event;
    time process_begin_time;
	uvm_event process_end_event;
    time process_end_time;
	
	function new(string name = "panda_blk_ctrl_abstract_trans");
		super.new(name);
		
		this.process_begin_event = this.get_event("process_begin");
		this.process_end_event = this.get_event("process_end");
	endfunction
	
	pure virtual function void unpack_params(panda_blk_ctrl_params params);
	pure virtual function panda_blk_ctrl_params pack_params();
	
	`panda_declare_begin_end_event_api(process)
	
	constraint c_valid_process_start_delay{
		`panda_delay_constraint(process_start_delay, this.configuration.start_delay)
	}
	
endclass

`endif
