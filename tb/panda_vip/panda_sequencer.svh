`ifndef __PANDA_SEQUENCER_H
`define __PANDA_SEQUENCER_H

`ifdef EN_ICB_MASTER_AGT
typedef tue_sequencer #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.REQ(panda_icb_master_trans),
	.RSP(panda_icb_master_trans),
	.PROXY_CONFIGURATION(panda_icb_configuration),
	.PROXY_STATUS(panda_icb_status)
)panda_icb_master_sequencer;
`endif

`ifdef EN_ICB_SLAVE_AGT
typedef tue_reactive_fifo_sequencer #(
	.CONFIGURATION(panda_icb_configuration),
	.STATUS(panda_icb_status),
	.ITEM(panda_icb_slave_trans),
	.RSP(panda_icb_slave_trans),
	.REQUEST(panda_icb_trans),
	.REQUEST_HANDLE(panda_icb_trans),
	.PROXY_CONFIGURATION(panda_icb_configuration),
	.PROXY_STATUS(panda_icb_status)
)panda_icb_slave_sequencer;
`endif

`ifdef EN_AXIS_MASTER_AGT
typedef tue_sequencer #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.REQ(panda_axis_master_trans),
	.RSP(panda_axis_master_trans),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
)panda_axis_master_sequencer;
`endif

`ifdef EN_AXIS_SLAVE_AGT
typedef tue_reactive_fifo_sequencer #(
	.CONFIGURATION(panda_axis_configuration),
	.STATUS(tue_status_dummy),
	.ITEM(panda_axis_slave_trans),
	.RSP(panda_axis_slave_trans),
	.REQUEST(panda_axis_trans),
	.REQUEST_HANDLE(panda_axis_trans),
	.PROXY_CONFIGURATION(panda_axis_configuration),
	.PROXY_STATUS(tue_status_dummy)
)panda_axis_slave_sequencer;
`endif

`endif
