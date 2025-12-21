`ifndef __PANDA_DRIVER_H
`define __PANDA_DRIVER_H

`ifdef EN_ICB_MASTER_AGT
class panda_icb_master_driver extends tue_driver #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.REQ(panda_icb_master_trans),
	.RSP(panda_icb_master_trans)
);
	
	local panda_icb_vif vif;
	
	local panda_icb_master_trans trans_fifo[$];
	local int trans_on_road_n;
	
	function new(string name = "panda_icb_master_driver", uvm_component parent = null);
		super.new(name, parent);
		
		this.trans_on_road_n = 0;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.vif = this.configuration.vif;
    endfunction
	
	task reset_phase(uvm_phase phase);
		this.do_cmd_reset();
		this.do_rsp_reset();
	endtask
	
	task main_phase(uvm_phase phase);
		fork
			forever
			begin
				panda_icb_master_trans tr;
				
				this.do_cmd_reset();
				
				this.seq_item_port.get_next_item(tr);
				
				wait(this.trans_on_road_n < this.configuration.outstanding_n);
				
				this.trans_fifo.push_back(tr);
				
				this.consume_delay(tr.request_valid_delay);
				
				this.vif.master_cb.cmd_addr <= tr.addr;
				this.vif.master_cb.cmd_read <= tr.is_read();
				this.vif.master_cb.cmd_wdata <= tr.is_read() ? {(`PANDA_ICB_MAX_DATA_WIDTH){1'bx}}:tr.data;
				this.vif.master_cb.cmd_wmask <= tr.is_read() ? {(`PANDA_ICB_MAX_DATA_WIDTH/8){1'bx}}:tr.strobe;
				this.vif.master_cb.cmd_valid <= 1'b1;
				
				this.consume_delay(1);
				
				this.trans_on_road_n++;
				
				while(!(this.vif.cmd_valid & this.vif.master_cb.cmd_ready))
				begin
					this.consume_delay(1);
				end
				
				this.seq_item_port.item_done();
			end
			
			forever
			begin
				panda_icb_master_trans tr;
				
				this.vif.master_cb.rsp_ready <= 1'b1;
				
				do
				begin
					this.consume_delay(1);
				end
				while(!(this.vif.master_cb.rsp_valid & this.vif.rsp_ready));
				
				this.trans_on_road_n--;
				
				if(this.trans_fifo.size() == 0)
					`uvm_fatal("panda_icb_master_driver", "rsp before cmd")
				
				tr = this.trans_fifo.pop_front();
				
				this.vif.master_cb.rsp_ready <= 1'b0;
				
				this.consume_delay(tr.response_ready_delay);
			end
		join
	endtask
	
	local task do_cmd_reset();
		this.vif.master_cb.cmd_addr <= {(`PANDA_ICB_MAX_ADDR_WIDTH){1'bx}};
		this.vif.master_cb.cmd_read <= 1'bx;
		this.vif.master_cb.cmd_wdata <= {(`PANDA_ICB_MAX_DATA_WIDTH){1'bx}};
		this.vif.master_cb.cmd_wmask <= {(`PANDA_ICB_MAX_DATA_WIDTH/8){1'bx}};
		this.vif.master_cb.cmd_valid <= 1'b0;
    endtask
	
	local task do_rsp_reset();
		this.vif.master_cb.rsp_ready <= this.configuration.default_rsp_ready;
    endtask
	
	local task consume_delay(int delay);
		repeat(delay)
			@(this.vif.master_cb);
	endtask
	
    `uvm_component_utils(panda_icb_master_driver)
	
endclass
`endif

`ifdef EN_ICB_SLAVE_AGT
class panda_icb_slave_driver extends tue_driver #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.REQ(panda_icb_slave_trans),
	.RSP(panda_icb_slave_trans)
);
	
	local panda_icb_vif vif;
	
	local panda_icb_slave_trans trans_fifo[$];
	local panda_icb_slave_trans trans_rsp_pending_queue[$];
	
	local semaphore sema;
	
	function new(string name = "panda_icb_slave_driver", uvm_component parent = null);
		super.new(name, parent);
		
		this.sema = new(1);
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.vif = this.configuration.vif;
    endfunction
	
	task reset_phase(uvm_phase phase);
		this.do_cmd_reset();
		this.do_rsp_reset();
	endtask
	
	task main_phase(uvm_phase phase);
		fork
			forever
			begin
				panda_icb_slave_trans tr;
				
				this.vif.slave_cb.cmd_ready <= 1'b1;
				
				do
				begin
					this.consume_delay(1);
				end
				while(!(this.vif.slave_cb.cmd_valid & this.vif.cmd_ready));
				
				this.vif.slave_cb.cmd_ready <= 1'b0;
				
				wait(this.trans_fifo.size() > 0);
				
				tr = this.trans_fifo.pop_front();
				
				this.consume_delay(tr.request_ready_delay);
			end
			
			forever
			begin
				panda_icb_slave_trans tr;
				
				this.do_rsp_reset();
				
				wait(this.trans_rsp_pending_queue.size() > 0);
				wait(this.trans_rsp_pending_queue[0].response_valid_delay == 0);
				
				this.sema.get(1);
				tr = this.trans_rsp_pending_queue.pop_front();
				this.sema.put(1);
				
				this.vif.slave_cb.rsp_rdata <= 
					(tr.access_type == PANDA_ICB_READ_ACCESS) ? tr.data:{(`PANDA_ICB_MAX_DATA_WIDTH){1'bx}};
				this.vif.slave_cb.rsp_err <= (tr.response == PANDA_ICB_RSP_ERR) ? 1'b1:1'b0;
				this.vif.slave_cb.rsp_valid <= 1'b1;
				
				do
				begin
					this.consume_delay(1);
				end
				while(!(this.vif.rsp_valid & this.vif.slave_cb.rsp_ready));
			end
			
			forever
			begin
				panda_icb_slave_trans tr;
				
				this.seq_item_port.get_next_item(tr);
				
				this.trans_fifo.push_back(tr);
				this.sema.get(1);
				this.trans_rsp_pending_queue.push_back(tr);
				this.sema.put(1);
				
				this.seq_item_port.item_done();
			end
			
			forever
			begin
				this.consume_delay(1);
				
				this.sema.get(1);
				foreach(this.trans_rsp_pending_queue[i])
				begin
					if(this.trans_rsp_pending_queue[i].response_valid_delay > 0)
						this.trans_rsp_pending_queue[i].response_valid_delay--;
				end
				this.sema.put(1);
			end
		join
	endtask
	
	local task do_cmd_reset();
		this.vif.slave_cb.cmd_ready <= this.configuration.default_rsp_ready;
    endtask
	
	local task do_rsp_reset();
		this.vif.slave_cb.rsp_rdata <= {(`PANDA_ICB_MAX_DATA_WIDTH){1'bx}};
		this.vif.slave_cb.rsp_err <= 1'bx;
		this.vif.slave_cb.rsp_valid <= 1'b0;
    endtask
	
	local task consume_delay(int delay);
		repeat(delay)
			@(this.vif.slave_cb);
	endtask
	
	`uvm_component_utils(panda_icb_slave_driver)
	
endclass
`endif

`ifdef EN_AXIS_MASTER_AGT
class panda_axis_master_driver extends tue_driver #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(panda_axis_master_trans),
	.RSP(panda_axis_master_trans)
);
	
	local panda_axis_vif vif;
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.vif = this.configuration.vif;
    endfunction
	
	task reset_phase(uvm_phase phase);
		this.do_reset();
	endtask
	
	task main_phase(uvm_phase phase);
		forever
		begin
			panda_axis_master_trans tr;
			
			this.seq_item_port.get_next_item(tr);
			
			for(int i = 0;i < tr.get_len();i++)
			begin
				this.do_reset();
				
				this.consume_delay(tr.get_stream_valid_delay(i));
				
				this.vif.master_cb.data <= tr.get_data(i);
				this.vif.master_cb.keep <= tr.get_keep(i);
				this.vif.master_cb.strb <= tr.get_strb(i);
				this.vif.master_cb.last <= (i == (tr.get_len() - 1)) ? 1'b1:1'b0;
				this.vif.master_cb.user <= tr.get_user(i);
				this.vif.master_cb.valid <= 1'b1;
				
				do
				begin
					this.consume_delay(1);
				end
				while(!(this.vif.valid & this.vif.master_cb.ready));
				
				this.do_reset();
			end
			
			this.seq_item_port.item_done();
		end
	endtask
	
	local task do_reset();
		this.vif.master_cb.data <= {(`PANDA_AXIS_MAX_DATA_WIDTH){1'bx}};
		this.vif.master_cb.keep <= {(`PANDA_AXIS_MAX_DATA_WIDTH/8){1'bx}};
		this.vif.master_cb.strb <= {(`PANDA_AXIS_MAX_DATA_WIDTH/8){1'bx}};
		this.vif.master_cb.last <= 1'bx;
		this.vif.master_cb.user <= {(`PANDA_AXIS_MAX_USER_WIDTH){1'bx}};
		this.vif.master_cb.valid <= 1'b0;
    endtask
	
	local task consume_delay(int delay);
		repeat(delay)
			@(this.vif.master_cb);
	endtask
	
	`tue_component_default_constructor(panda_axis_master_driver)
	`uvm_component_utils(panda_axis_master_driver)
	
endclass
`endif

`ifdef EN_AXIS_SLAVE_AGT
class panda_axis_slave_driver extends tue_driver #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(panda_axis_slave_trans),
	.RSP(panda_axis_slave_trans)
);
	
	local panda_axis_vif vif;
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.vif = this.configuration.vif;
    endfunction
	
	task reset_phase(uvm_phase phase);
		this.do_reset();
	endtask
	
	task main_phase(uvm_phase phase);
		forever
		begin
			panda_axis_slave_trans tr;
			
			this.vif.slave_cb.ready <= 1'b1;
			
			while(!(this.vif.slave_cb.valid & this.vif.ready))
				this.consume_delay(1);
			
			this.vif.slave_cb.ready <= 1'b0;
			
			this.seq_item_port.get_next_item(tr);
			
			tr.init_req(this.vif.slave_cb.data, this.vif.slave_cb.keep, this.vif.slave_cb.strb, this.vif.slave_cb.user);
			
			this.consume_delay(tr.get_ready_delay());
			
			this.vif.slave_cb.ready <= 1'b1;
			
			if(tr.get_ready_delay() == 0)
				this.consume_delay(1);
			
			this.seq_item_port.item_done();
		end
	endtask
	
	local task do_reset();
		this.vif.slave_cb.ready <= this.configuration.default_ready;
    endtask
	
	local task consume_delay(int delay);
		repeat(delay)
			@(this.vif.slave_cb);
	endtask
	
	`tue_component_default_constructor(panda_axis_slave_driver)
	`uvm_component_utils(panda_axis_slave_driver)
	
endclass
`endif

`ifdef EN_BLK_CTRL_MASTER_AGT
class panda_blk_ctrl_master_driver extends tue_driver #(
	.CONFIGURATION(panda_blk_ctrl_configuration),
	.STATUS(tue_status_dummy),
	.REQ(panda_blk_ctrl_abstract_trans),
	.RSP(panda_blk_ctrl_abstract_trans)
);
	
	local panda_blk_ctrl_vif vif;
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
		
		this.vif = this.configuration.vif;
    endfunction
	
	task reset_phase(uvm_phase phase);
		this.do_reset();
	endtask
	
	task main_phase(uvm_phase phase);
		this.consume_delay(1);
		
		forever
		begin
			panda_blk_ctrl_abstract_trans tr;
			
			this.seq_item_port.get_next_item(tr);
			
			this.consume_delay(tr.process_start_delay);
			
			this.vif.master_cb.params <= tr.pack_params();
			this.vif.master_cb.start <= 1'b1;
			
			this.consume_delay(1);
			
			this.vif.master_cb.start <= 1'b0;
			
			while(!this.vif.master_cb.done)
				this.consume_delay(1);
			
			this.do_reset();
			
			this.seq_item_port.item_done();
		end
	endtask
	
	local task do_reset();
		this.vif.master_cb.params <= {(`PANDA_BLK_CTRL_MAX_PARAMS_WIDTH){1'bx}};
		this.vif.master_cb.start <= 1'b0;
    endtask
	
	local task consume_delay(int delay);
		repeat(delay)
			@(this.vif.master_cb);
	endtask
	
	`tue_component_default_constructor(panda_blk_ctrl_master_driver)
	`uvm_component_utils(panda_blk_ctrl_master_driver)
	
endclass
`endif

`endif
