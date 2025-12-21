`ifndef __PANDA_MONITOR_H
`define __PANDA_MONITOR_H

class panda_icb_monitor_base #(
	type BASE = tue_param_monitor
)extends BASE;
	
	local panda_icb_vif vif;
	
	local panda_icb_trans trans_fifo[$];
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.vif = this.configuration.vif;
    endfunction
	
	task main_phase(uvm_phase phase);
		fork
			forever
			begin
				panda_icb_trans tr;
				
				while(!this.vif.monitor_cb.cmd_valid)
				begin
					@(this.vif.monitor_cb);
				end
				
				tr = this.create_item("icb_tr");
				
				tr.access_type = this.vif.monitor_cb.cmd_read ? PANDA_ICB_READ_ACCESS:PANDA_ICB_WRITE_ACCESS;
				tr.addr = this.vif.monitor_cb.cmd_addr;
				if(!this.vif.monitor_cb.cmd_read)
				begin
					tr.data = this.vif.monitor_cb.cmd_wdata;
					tr.strobe = this.vif.monitor_cb.cmd_wmask;
				end
				
				tr.begin_request(0);
				
				while(!(this.vif.monitor_cb.cmd_valid & this.vif.monitor_cb.cmd_ready))
				begin
					@(this.vif.monitor_cb);
				end
				
				tr.end_request(0);
				
				this.trans_fifo.push_back(tr);
				
				if(tr.is_write())
					this.status.memory.put(tr.data, tr.strobe, this.configuration.data_width / 8, tr.addr, 0);
				
				this.do_write_request(tr);
				
				do
				begin
					@(this.vif.monitor_cb);
				end
				while(!this.vif.monitor_cb.cmd_valid);
			end
			
			forever
			begin
				while(!this.vif.monitor_cb.rsp_valid)
				begin
					@(this.vif.monitor_cb);
				end
				
				if(this.trans_fifo.size() == 0)
				begin
					`uvm_error(get_name(), "rsp before cmd!")
					
					break;
				end
				else
				begin
					panda_icb_trans tr;
					
					tr = this.trans_fifo.pop_front();
					
					tr.begin_response(0);
					
					while(!(this.vif.monitor_cb.rsp_valid & this.vif.monitor_cb.rsp_ready))
					begin
						@(this.vif.monitor_cb);
					end
					
					if(tr.is_read())
						tr.data = this.vif.monitor_cb.rsp_rdata;
					tr.response = this.vif.monitor_cb.rsp_err ? PANDA_ICB_RSP_ERR:PANDA_ICB_RSP_OK;
					
					tr.end_response(0);
					
					this.write_item(tr);
				end
				
				do
				begin
					@(this.vif.monitor_cb);
				end
				while(!this.vif.monitor_cb.rsp_valid);
			end
		join
	endtask
	
	virtual function void do_write_request(panda_icb_trans request);
		`uvm_fatal(get_name(), "do_write_request not implemented!")
	endfunction
	
	`tue_component_default_constructor(panda_icb_monitor_base)
	
endclass

`ifdef EN_ICB_MASTER_AGT
class panda_icb_master_monitor extends panda_icb_monitor_base #(
	.BASE(tue_param_monitor #(
		.CONFIGURATION(panda_icb_configuration),
		.STATUS(panda_icb_status),
		.ITEM(panda_icb_trans),
		.ITEM_HANDLE(panda_icb_trans)
	))
);
	
	function void do_write_request(panda_icb_trans request);
		// pass
	endfunction
	
	`tue_component_default_constructor(panda_icb_master_monitor)
	`uvm_component_utils(panda_icb_master_monitor)
	
endclass
`endif

`ifdef EN_ICB_SLAVE_AGT
class panda_icb_slave_monitor extends panda_icb_monitor_base #(
	.BASE(tue_reactive_monitor #(
		.CONFIGURATION(panda_icb_configuration),
		.STATUS(panda_icb_status),
		.ITEM(panda_icb_trans),
		.ITEM_HANDLE(panda_icb_trans)
	))
);
	
	function void do_write_request(panda_icb_trans request);
		this.write_request(request.clone());
	endfunction
	
	`tue_component_default_constructor(panda_icb_slave_monitor)
	`uvm_component_utils(panda_icb_slave_monitor)
	
endclass
`endif

class panda_axis_monitor_base #(
	type BASE = tue_param_monitor
)extends BASE;
	
	local panda_axis_vif vif;
	
	local panda_axis_data data_fifo[$];
	local panda_axis_mask keep_fifo[$];
	local panda_axis_mask strb_fifo[$];
	local panda_axis_user user_fifo[$];
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.vif = this.configuration.vif;
    endfunction
	
	task main_phase(uvm_phase phase);
		forever
		begin
			bit is_last;
			int now_len;
			panda_axis_trans tr;
			
			now_len = 0;
			tr = this.create_item("axis_tr");
			
			while(!(this.vif.monitor_cb.valid))
				@(this.vif.monitor_cb);
			
			tr.begin_stream(0);
			
			do
			begin
				panda_axis_trans req;
				
				while(!(this.vif.monitor_cb.valid))
					@(this.vif.monitor_cb);
				
				req = panda_axis_trans::type_id::create("req_panda_axis_trans");
				req.set_configuration(this.configuration);
				req.init_req(
					this.vif.monitor_cb.data,
					this.vif.monitor_cb.keep,
					this.vif.monitor_cb.strb,
					this.vif.monitor_cb.user
				);
				
				this.do_write_request(req);
				
				while(!(this.vif.monitor_cb.valid & this.vif.monitor_cb.ready))
					@(this.vif.monitor_cb);
				
				this.data_fifo.push_back(this.vif.monitor_cb.data);
				if(this.configuration.has_keep)
					this.keep_fifo.push_back(this.vif.monitor_cb.keep);
				if(this.configuration.has_strb)
					this.strb_fifo.push_back(this.vif.monitor_cb.strb);
				if(this.configuration.user_width > 0)
					this.user_fifo.push_back(this.vif.monitor_cb.user);
				
				now_len++;
				
				is_last = (!this.configuration.has_last) || this.vif.monitor_cb.last;
				
				if(is_last)
				begin
					tr.len = now_len;
					tr.put_data(this.data_fifo);
					if(this.configuration.has_keep)
						tr.put_keep(this.keep_fifo);
					if(this.configuration.has_strb)
						tr.put_strb(this.strb_fifo);
					if(this.configuration.user_width > 0)
						tr.put_user(this.user_fifo);
					
					tr.end_stream(0);
				end
				
				@(this.vif.monitor_cb);
			end
			while(!is_last);
			
			this.write_item(tr);
			
			this.data_fifo.delete();
			this.keep_fifo.delete();
			this.strb_fifo.delete();
			this.user_fifo.delete();
		end
	endtask
	
	virtual function void do_write_request(panda_axis_trans request);
		`uvm_fatal(get_name(), "do_write_request not implemented!")
	endfunction
	
	`tue_component_default_constructor(panda_axis_monitor_base)
	
endclass

`ifdef EN_AXIS_MASTER_AGT
class panda_axis_master_monitor extends panda_axis_monitor_base #(
	.BASE(tue_param_monitor #(
		.CONFIGURATION(panda_axis_configuration),
		.STATUS(tue_status_dummy),
		.ITEM(panda_axis_trans),
		.ITEM_HANDLE(panda_axis_trans)
	))
);
	
	function void do_write_request(panda_axis_trans request);
		// pass
	endfunction
	
	`tue_component_default_constructor(panda_axis_master_monitor)
	`uvm_component_utils(panda_axis_master_monitor)
	
endclass
`endif

`ifdef EN_AXIS_SLAVE_AGT
class panda_axis_slave_monitor extends panda_axis_monitor_base #(
	.BASE(tue_reactive_monitor #(
		.CONFIGURATION(panda_axis_configuration),
		.STATUS(tue_status_dummy),
		.ITEM(panda_axis_trans),
		.ITEM_HANDLE(panda_axis_trans)
	))
);
	
	function void do_write_request(panda_axis_trans request);
		this.write_request(request.clone());
	endfunction
	
	`tue_component_default_constructor(panda_axis_slave_monitor)
	`uvm_component_utils(panda_axis_slave_monitor)
	
endclass
`endif

class panda_blk_ctrl_monitor_base #(
	type BASE = tue_param_monitor
)extends BASE;
	
	local panda_blk_ctrl_vif vif;
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.vif = this.configuration.vif;
    endfunction
	
	task main_phase(uvm_phase phase);
		forever
		begin
			panda_blk_ctrl_abstract_trans tr;
			
			tr = this.create_item("blk_ctrl_tr");
			
			while(!(this.vif.monitor_cb.idle & this.vif.monitor_cb.start))
				@(this.vif.monitor_cb);
			
			tr.begin_process(0);
			
			tr.unpack_params(this.vif.monitor_cb.params);
			
			this.do_write_request(tr);
			
			if(!this.configuration.complete_monitor_mode)
				this.write_item(tr);
			
			do
			begin
				@(this.vif.monitor_cb);
			end
			while(!this.vif.monitor_cb.done);
			
			if(this.configuration.complete_monitor_mode)
			begin
				tr.end_process(0);
				
				this.write_item(tr);
			end
		end
	endtask
	
	virtual function panda_blk_ctrl_abstract_trans create_item(
		string item_name = "item",
		string stream_name = "main",
		string label = "",
		string desc = "",
		time begin_time = 0,
		int parent_handle = 0
	);
		uvm_sequence_item item_base;
		panda_blk_ctrl_abstract_trans item;
		
		item_base = this.configuration.tr_factory.create_item();
		
		if(!$cast(item, item_base))
			`uvm_fatal(this.get_name(), "cannot cast to panda_blk_ctrl_abstract_trans!")
		
		item.set_context(this.configuration, this.status);
		void'(this.begin_tr(item, stream_name, label, desc, begin_time, parent_handle));
		
		return item;
	endfunction
	
	virtual function void do_write_request(panda_blk_ctrl_abstract_trans request);
		`uvm_fatal(get_name(), "do_write_request not implemented!")
	endfunction
	
	`tue_component_default_constructor(panda_blk_ctrl_monitor_base)
	
endclass

`ifdef EN_BLK_CTRL_MASTER_AGT
class panda_blk_ctrl_master_monitor extends panda_blk_ctrl_monitor_base #(
	.BASE(tue_param_monitor #(
		.CONFIGURATION(panda_blk_ctrl_configuration),
		.STATUS(tue_status_dummy),
		.ITEM(panda_blk_ctrl_abstract_trans),
		.ITEM_HANDLE(panda_blk_ctrl_abstract_trans)
	))
);
	
	function void do_write_request(panda_blk_ctrl_abstract_trans request);
		// pass
	endfunction
	
	`tue_component_default_constructor(panda_blk_ctrl_master_monitor)
	`uvm_component_utils(panda_blk_ctrl_master_monitor)
	
endclass
`endif

`endif
