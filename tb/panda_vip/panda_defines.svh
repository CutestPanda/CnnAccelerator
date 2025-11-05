`ifndef __PANDA_DEFINES_H
`define __PANDA_DEFINES_H

`ifndef TIMEPRECISION
`define TIMEPRECISION 1ps
`endif

// `define EN_ICB_MASTER_AGT
// `define EN_ICB_SLAVE_AGT
// `define EN_AXIS_MASTER_AGT
// `define EN_AXIS_SLAVE_AGT
// `define EN_BLK_CTRL_MASTER_AGT

typedef virtual panda_clock_if panda_clock_vif;
typedef virtual panda_reset_if panda_reset_vif;
typedef virtual panda_icb_if panda_icb_vif;
typedef virtual panda_axis_if panda_axis_vif;
typedef virtual panda_blk_ctrl_if panda_blk_ctrl_vif;

`ifndef PANDA_ICB_MAX_ADDR_WIDTH
	`define PANDA_ICB_MAX_ADDR_WIDTH 32
`endif

`ifndef PANDA_ICB_MAX_DATA_WIDTH
	`define PANDA_ICB_MAX_DATA_WIDTH 32
`endif

typedef enum{
	PANDA_ICB_ACCESS_TYPE_NOT_SET,
	PANDA_ICB_WRITE_ACCESS,
    PANDA_ICB_READ_ACCESS
}panda_icb_access_type;

typedef enum{
	PANDA_ICB_RSP_OK,
    PANDA_ICB_RSP_ERR
}panda_icb_response_type;

typedef logic[`PANDA_ICB_MAX_ADDR_WIDTH-1:0] panda_icb_address;
typedef logic[`PANDA_ICB_MAX_DATA_WIDTH-1:0] panda_icb_data;
typedef logic[`PANDA_ICB_MAX_DATA_WIDTH/8-1:0] panda_icb_strobe;

`ifndef PANDA_AXIS_MAX_DATA_WIDTH
	`define PANDA_AXIS_MAX_DATA_WIDTH 512
`endif

`ifndef PANDA_AXIS_MAX_USER_WIDTH
	`define PANDA_AXIS_MAX_USER_WIDTH 16
`endif

typedef logic[`PANDA_AXIS_MAX_DATA_WIDTH-1:0] panda_axis_data;
typedef logic[`PANDA_AXIS_MAX_DATA_WIDTH/8-1:0] panda_axis_mask;
typedef logic[`PANDA_AXIS_MAX_USER_WIDTH-1:0] panda_axis_user;

`ifndef PANDA_BLK_CTRL_MAX_PARAMS_WIDTH
	`define PANDA_BLK_CTRL_MAX_PARAMS_WIDTH 256
`endif

typedef logic[`PANDA_BLK_CTRL_MAX_PARAMS_WIDTH-1:0] panda_blk_ctrl_params;

`endif
