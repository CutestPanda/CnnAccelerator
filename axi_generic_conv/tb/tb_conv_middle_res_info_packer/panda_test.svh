`ifndef __PANDA_TEST_H
`define __PANDA_TEST_H

class MidResInfoPackerVsqr extends tue_sequencer_base #(
	.BASE(uvm_sequencer),
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(tue_configuration_dummy),
	.PROXY_STATUS(tue_status_dummy)
);
	
	panda_axis_master_sequencer fm_cake_info_sqr;
	panda_axis_master_sequencer mac_array_sqr;
	
	`tue_component_default_constructor(MidResInfoPackerVsqr)
	`uvm_component_utils(MidResInfoPackerVsqr)
	
endclass

class MidResInfoPackerVseq0 extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local MidResInfoPackerCfg test_cfg;
	
	local rand int test_cake_n;
	local rand int fm_cake_h[];
	
	`uvm_declare_p_sequencer(MidResInfoPackerVsqr)
	
	function new(string name = "MidResInfoPackerVseq0");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(MidResInfoPackerCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
		
		if(!this.randomize() with {
			test_cake_n == 3;
			
			fm_cake_h.size() == test_cake_n;
			
			foreach(fm_cake_h[i]){
				fm_cake_h[i] dist {1:/3, 2:/1, 3:/1};
			}
		})
			`uvm_fatal(this.get_name(), "cannot randomize!!!")
	endtask
	
	task body();
		panda_axis_master_trans fm_cake_info_tr;
		panda_axis_master_trans mac_array_tr;
		
		fork
			begin
				for(int k = 0;k < this.test_cake_n;k++)
				begin
					`uvm_do_on_with(fm_cake_info_tr, this.p_sequencer.fm_cake_info_sqr, {
						data[0][3:0] == fm_cake_h[k];
					})
				end
			end
			
			begin
				for(int k = 0;k < this.test_cake_n;k++)
				begin
					for(int c = 0;c < this.test_cfg.cgrp_n_of_fmap_region_that_kernal_set_sel;c++)
					begin
						for(int y = 0;y < this.fm_cake_h[k];y++)
						begin
							for(int m = 0;m < this.test_cfg.kernal_w;m++)
							begin
								for(int x = 0;x < this.test_cfg.ofmap_w;x++)
								begin
									for(int p = 0;p < this.test_cfg.cal_round_n;p++)
									begin
										`uvm_do_on_with(mac_array_tr, this.p_sequencer.mac_array_sqr, {
											data[0] == x;
											
											user[0][0] == (p == (test_cfg.cal_round_n-1));
										})
									end
								end
							end
						end
					end
				end
			end
		join
	endtask
	
	`uvm_object_utils(MidResInfoPackerVseq0)
	
endclass

class conv_middle_res_info_packer_test extends panda_test_single_clk_base #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local MidResInfoPackerVsqr mid_res_info_packer_vsqr;
	
	local panda_axis_master_agent fm_cake_info_agt;
	local panda_axis_master_agent mac_array_agt;
	local panda_axis_slave_agent pkt_out_agt;
	
	local panda_axis_configuration fm_cake_info_cfg;
	local panda_axis_configuration mac_array_cfg;
	local panda_axis_configuration pkt_out_cfg;
	
	local MidResInfoPackerCfg test_cfg;
	
	function new(string name = "conv_middle_res_info_packer_test", uvm_component parent = null);
		super.new(name, parent);
		
		this.clk_period = 10ns;
		this.rst_duration = 1us;
		this.main_phase_drain_time = 10us;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(MidResInfoPackerCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
		
		this.fm_cake_info_cfg = panda_axis_configuration::type_id::create("fm_cake_info_cfg");
		if(!this.fm_cake_info_cfg.randomize() with {
			data_width == 8;
			user_width == 0;
			
			valid_delay.min_delay == 50;
			valid_delay.mid_delay[0] == 60;
			valid_delay.mid_delay[1] == 80;
			valid_delay.max_delay == 100;
			valid_delay.weight_zero_delay == 0;
			valid_delay.weight_short_delay == 2;
			valid_delay.weight_long_delay == 1;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize fm_cake_info_cfg!")
		
		this.mac_array_cfg = panda_axis_configuration::type_id::create("mac_array_cfg");
		if(!this.mac_array_cfg.randomize() with {
			data_width == (test_cfg.atomic_k * 48);
			user_width == (test_cfg.atomic_k + 1);
			
			valid_delay.min_delay == 0;
			valid_delay.mid_delay[0] == 2;
			valid_delay.mid_delay[1] == 3;
			valid_delay.max_delay == 3;
			valid_delay.weight_zero_delay == 3;
			valid_delay.weight_short_delay == 2;
			valid_delay.weight_long_delay == 1;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize mac_array_cfg!")
		
		this.pkt_out_cfg = panda_axis_configuration::type_id::create("pkt_out_cfg");
		if(!this.pkt_out_cfg.randomize() with {
			data_width == (test_cfg.atomic_k * 48);
			user_width == 2;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 1;
			ready_delay.mid_delay[1] == 1;
			ready_delay.max_delay == 3;
			ready_delay.weight_zero_delay == 3;
			ready_delay.weight_short_delay == 1;
			ready_delay.weight_long_delay == 1;
			
			default_ready == 1'b1;
			has_keep == 1'b1;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize pkt_out_cfg!")
		
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "fm_cake_info_vif_m", this.fm_cake_info_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for fm_cake_info_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "mac_array_vif_m", this.mac_array_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for mac_array_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "pkt_out_vif_s", this.pkt_out_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for pkt_out_vif_s!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.mid_res_info_packer_vsqr = MidResInfoPackerVsqr::type_id::create("main_vsqr", this);
		
		this.fm_cake_info_agt = panda_axis_master_agent::type_id::create("fm_cake_info_agt", this);
		this.fm_cake_info_agt.active_agent();
		this.fm_cake_info_agt.set_configuration(this.fm_cake_info_cfg);
		
		this.mac_array_agt = panda_axis_master_agent::type_id::create("mac_array_agt", this);
		this.mac_array_agt.active_agent();
		this.mac_array_agt.set_configuration(this.mac_array_cfg);
		
		this.pkt_out_agt = panda_axis_slave_agent::type_id::create("pkt_out_agt", this);
		this.pkt_out_agt.active_agent();
		this.pkt_out_agt.set_configuration(this.pkt_out_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.mid_res_info_packer_vsqr.fm_cake_info_sqr = this.fm_cake_info_agt.sequencer;
		this.mid_res_info_packer_vsqr.mac_array_sqr = this.mac_array_agt.sequencer;
		
		this.mid_res_info_packer_vsqr.set_default_sequence("main_phase", MidResInfoPackerVseq0::type_id::get());
		this.pkt_out_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
	endfunction
	
	`uvm_component_utils(conv_middle_res_info_packer_test)
	
endclass

`endif
