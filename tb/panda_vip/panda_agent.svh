`ifndef __PANDA_AGENT_H
`define __PANDA_AGENT_H

`ifdef EN_ICB_MASTER_AGT
class panda_icb_master_agent extends tue_param_agent #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.ITEM(panda_icb_trans),
	.MONITOR(panda_icb_master_monitor),
	.SEQUENCER(panda_icb_master_sequencer),
	.DRIVER(panda_icb_master_driver),
	.ENABLE_PASSIVE_SEQUENCER(0)
);
	
	`tue_component_default_constructor(panda_icb_master_agent)
	`uvm_component_utils(panda_icb_master_agent)
	
endclass
`endif

`ifdef EN_ICB_SLAVE_AGT
class panda_icb_slave_agent extends tue_reactive_agent #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.ITEM(panda_icb_trans),
	.MONITOR(panda_icb_slave_monitor),
	.SEQUENCER(panda_icb_slave_sequencer),
	.DRIVER(panda_icb_slave_driver),
	.ENABLE_PASSIVE_SEQUENCER(0)
);
	
	`tue_component_default_constructor(panda_icb_slave_agent)
	`uvm_component_utils(panda_icb_slave_agent)
	
endclass
`endif

`ifdef EN_AXIS_MASTER_AGT
class panda_axis_master_agent extends tue_param_agent #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.ITEM(panda_axis_trans),
	.MONITOR(panda_axis_master_monitor),
	.SEQUENCER(panda_axis_master_sequencer),
	.DRIVER(panda_axis_master_driver),
	.ENABLE_PASSIVE_SEQUENCER(0)
);
	
	`tue_component_default_constructor(panda_axis_master_agent)
	`uvm_component_utils(panda_axis_master_agent)
	
endclass
`endif

`ifdef EN_AXIS_SLAVE_AGT
class panda_axis_slave_agent extends tue_reactive_agent #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.ITEM(panda_axis_trans),
	.MONITOR(panda_axis_slave_monitor),
	.SEQUENCER(panda_axis_slave_sequencer),
	.DRIVER(panda_axis_slave_driver),
	.ENABLE_PASSIVE_SEQUENCER(0)
);
	
	`tue_component_default_constructor(panda_axis_slave_agent)
	`uvm_component_utils(panda_axis_slave_agent)
	
endclass
`endif

`endif
