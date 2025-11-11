`ifndef __PANDA_TEST_H
`define __PANDA_TEST_H

class PhyFmapSfcRowAdapterVsqr extends tue_sequencer_base #(
	.BASE(uvm_sequencer),
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy),
	.PROXY_CONFIGURATION(tue_configuration_dummy),
	.PROXY_STATUS(tue_status_dummy)
);
	
	panda_axis_master_sequencer rst_adapter_sqr;
	panda_axis_master_sequencer incr_traffic_sqr;
	panda_axis_master_sequencer m_fmap_row_axis_sqr;
	
	`tue_component_default_constructor(PhyFmapSfcRowAdapterVsqr)
	`uvm_component_utils(PhyFmapSfcRowAdapterVsqr)
	
endclass

class EmptySingleAxisSeq extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	function new(string name = "EmptySingleAxisSeq");
		super.new(name);
		
		this.set_automatic_phase_objection(0);
    endfunction
	
	task body();
		panda_axis_master_trans tr;
		
		`uvm_do_with(tr, {
			data[0] == 0;
		})
    endtask
	
	`uvm_object_utils(EmptySingleAxisSeq)
	
endclass

typedef EmptySingleAxisSeq RstAdapterSeq;
typedef EmptySingleAxisSeq IncrTrafficSeq;

class PhyFmapSfcRowAdapterVseq0 extends tue_sequence #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(uvm_sequence_item),
	.RSP(uvm_sequence_item),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
);
	
	local PhyFmapSfcRowAdapterCfg test_cfg;
	
	`uvm_declare_p_sequencer(PhyFmapSfcRowAdapterVsqr)
	
	function new(string name = "PhyFmapSfcRowAdapterVseq0");
		super.new(name);
		
		this.set_automatic_phase_objection(1);
    endfunction
	
	task pre_body();
		super.pre_body();
		
		if(!uvm_config_db #(PhyFmapSfcRowAdapterCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
	endtask
	
	task body();
		RstAdapterSeq rst_seq;
		IncrTrafficSeq incr_traffic_seq;
		panda_axis_master_trans m_fmap_row_axis_tr;
		
		`uvm_do_on_with(rst_seq, this.p_sequencer.rst_adapter_sqr, {})
		
		fork
			repeat(4)
			begin
				`uvm_do_on_with(incr_traffic_seq, this.p_sequencer.incr_traffic_sqr, {})
			end
			
			repeat(4 * this.test_cfg.kernal_w)
			begin
				`uvm_do_on_with(m_fmap_row_axis_tr, this.p_sequencer.m_fmap_row_axis_sqr, {
					len == test_cfg.ifmap_w;
					
					foreach(data[i]){
						data[i] == i;
					}
				})
			end
		join
	endtask
	
	`uvm_object_utils(PhyFmapSfcRowAdapterVseq0)
	
endclass

class phy_fmap_sfc_row_adapter_test extends panda_test_single_clk_base #(
	.CONFIGURATION(tue_configuration_dummy),
	.STATUS(tue_status_dummy)
);
	
	local PhyFmapSfcRowAdapterVsqr phy_fmap_sfc_row_adapter_vsqr;
	
	local panda_axis_master_agent rst_adapter_agt;
	local panda_axis_master_agent incr_traffic_agt;
	local panda_axis_master_agent fmap_row_axis_mst_agt;
	local panda_axis_slave_agent mac_array_slv_agt;
	
	local panda_axis_configuration rst_adapter_cfg;
	local panda_axis_configuration incr_traffic_cfg;
	local panda_axis_configuration fmap_row_mst_cfg;
	local panda_axis_configuration mac_array_slv_cfg;
	
	local PhyFmapSfcRowAdapterCfg test_cfg;
	
	function new(string name = "phy_fmap_sfc_row_adapter_test", uvm_component parent = null);
		super.new(name, parent);
		
		this.clk_period = 10ns;
		this.rst_duration = 1us;
		this.main_phase_drain_time = 10us;
	endfunction
	
	function void build_phase(uvm_phase phase);
		super.build_phase(phase);
	endfunction
	
	protected function void build_configuration();
		if(!uvm_config_db #(PhyFmapSfcRowAdapterCfg)::get(null, "", "test_cfg", this.test_cfg))
			`uvm_fatal(this.get_name(), "cannot get test_cfg!!!")
		
		this.rst_adapter_cfg = panda_axis_configuration::type_id::create("rst_adapter_cfg");
		if(!this.rst_adapter_cfg.randomize() with {
			data_width == 8;
			user_width == 0;
			
			valid_delay.min_delay == 0;
			valid_delay.mid_delay[0] == 0;
			valid_delay.mid_delay[1] == 0;
			valid_delay.max_delay == 0;
			valid_delay.weight_zero_delay == 1;
			valid_delay.weight_short_delay == 0;
			valid_delay.weight_long_delay == 0;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize rst_adapter_cfg!")
		
		this.incr_traffic_cfg = panda_axis_configuration::type_id::create("incr_traffic_cfg");
		if(!this.incr_traffic_cfg.randomize() with {
			data_width == 8;
			user_width == 0;
			
			valid_delay.min_delay == 100;
			valid_delay.mid_delay[0] == 150;
			valid_delay.mid_delay[1] == 200;
			valid_delay.max_delay == 300;
			valid_delay.weight_zero_delay == 0;
			valid_delay.weight_short_delay == 1;
			valid_delay.weight_long_delay == 1;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b0;
		})
			`uvm_fatal(this.get_name(), "cannot randomize incr_traffic_cfg!")
		
		this.fmap_row_mst_cfg = panda_axis_configuration::type_id::create("fmap_row_mst_cfg");
		if(!this.fmap_row_mst_cfg.randomize() with {
			data_width == (test_cfg.atomic_c * 16);
			user_width == 0;
			
			valid_delay.min_delay == 0;
			valid_delay.mid_delay[0] == 2;
			valid_delay.mid_delay[1] == 3;
			valid_delay.max_delay == 5;
			valid_delay.weight_zero_delay == 3;
			valid_delay.weight_short_delay == 2;
			valid_delay.weight_long_delay == 1;
			
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize fmap_row_mst_cfg!")
		
		this.mac_array_slv_cfg = panda_axis_configuration::type_id::create("mac_array_slv_cfg");
		if(!this.mac_array_slv_cfg.randomize() with {
			data_width == (test_cfg.atomic_c * 16);
			user_width == 1;
			
			ready_delay.min_delay == 0;
			ready_delay.mid_delay[0] == 1;
			ready_delay.mid_delay[1] == 1;
			ready_delay.max_delay == 3;
			ready_delay.weight_zero_delay == 3;
			ready_delay.weight_short_delay == 1;
			ready_delay.weight_long_delay == 1;
			
			default_ready == 1'b1;
			has_keep == 1'b0;
			has_strb == 1'b0;
			has_last == 1'b1;
		})
			`uvm_fatal(this.get_name(), "cannot randomize mac_array_slv_cfg!")
		
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "rst_adapter_vif_m", this.rst_adapter_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for rst_adapter_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "incr_traffic_vif_m", this.incr_traffic_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for incr_traffic_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "fmap_row_axis_vif_m", this.fmap_row_mst_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for fmap_row_axis_vif_m!!!")
		if(!uvm_config_db #(panda_axis_vif)::get(null, "", "mac_array_axis_vif_s", this.mac_array_slv_cfg.vif))
			`uvm_fatal(get_name(), "virtual interface must be set for mac_array_axis_vif_s!!!")
	endfunction
	
	protected function void build_status();
		// blank
	endfunction
	
	protected function void build_agents();
		this.phy_fmap_sfc_row_adapter_vsqr = PhyFmapSfcRowAdapterVsqr::type_id::create("main_vsqr", this);
		
		this.rst_adapter_agt = panda_axis_master_agent::type_id::create("rst_adapter_agt", this);
		this.rst_adapter_agt.active_agent();
		this.rst_adapter_agt.set_configuration(this.rst_adapter_cfg);
		
		this.incr_traffic_agt = panda_axis_master_agent::type_id::create("incr_traffic_agt", this);
		this.incr_traffic_agt.active_agent();
		this.incr_traffic_agt.set_configuration(this.incr_traffic_cfg);
		
		this.fmap_row_axis_mst_agt = panda_axis_master_agent::type_id::create("fmap_row_axis_mst_agt", this);
		this.fmap_row_axis_mst_agt.active_agent();
		this.fmap_row_axis_mst_agt.set_configuration(this.fmap_row_mst_cfg);
		
		this.mac_array_slv_agt = panda_axis_slave_agent::type_id::create("mac_array_slv_agt", this);
		this.mac_array_slv_agt.active_agent();
		this.mac_array_slv_agt.set_configuration(this.mac_array_slv_cfg);
	endfunction
	
	function void connect_phase(uvm_phase phase);
		this.phy_fmap_sfc_row_adapter_vsqr.rst_adapter_sqr = this.rst_adapter_agt.sequencer;
		this.phy_fmap_sfc_row_adapter_vsqr.incr_traffic_sqr = this.incr_traffic_agt.sequencer;
		this.phy_fmap_sfc_row_adapter_vsqr.m_fmap_row_axis_sqr = this.fmap_row_axis_mst_agt.sequencer;
		
		this.phy_fmap_sfc_row_adapter_vsqr.set_default_sequence("main_phase", PhyFmapSfcRowAdapterVseq0::type_id::get());
		this.mac_array_slv_agt.sequencer.set_default_sequence("main_phase", panda_axis_slave_default_sequence::type_id::get());
	endfunction
	
	`uvm_component_utils(phy_fmap_sfc_row_adapter_test)
	
endclass

`endif
