/************************************************************************************************************************
通用逐元素操作处理单元驱动
@brief  提供了通用逐元素操作处理的初始化、控制、状态获取、配置等API
@date   2026/01/16
@author 陈家耀
@eidt   2026.01.16 1.00 创建了第1个正式版本
************************************************************************************************************************/

#include "axi_element_wise_proc.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 逐元素操作处理单元的加速器类型编码
#define ELM_WISE_PROC_ACC_TYPE 0b110101101010110011000101100100

// 各寄存器域的偏移地址
#define REG_REGION_PROP_OFS 0x0000
#define REG_REGION_CTRL_OFS 0x0040
#define REG_REGION_STS_OFS 0x0060
#define REG_REGION_BUF_CFG_OFS 0x0080
#define REG_REGION_FU_CFG_OFS 0x00C0

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化通用逐元素操作处理单元
@param  handler 通用逐元素操作处理单元(加速器句柄)
        baseaddr 加速器基地址
@return 是否成功
*************************/
int axi_element_wise_proc_init(AxiElmWiseProcHandler* handler, uint32_t baseaddr){
	uint32_t* test_ptr = (uint32_t*)baseaddr;

	if((test_ptr[1] & 0x3FFFFFFF) != ELM_WISE_PROC_ACC_TYPE){
		return -1;
	}

	handler->reg_base_ptr = (uint32_t*)baseaddr;
	handler->reg_region_prop = (AxiElmWiseProcRegRgnProp*)(baseaddr + REG_REGION_PROP_OFS);
	handler->reg_region_ctrl = (AxiElmWiseProcRegRgnCtrl*)(baseaddr + REG_REGION_CTRL_OFS);
	handler->reg_region_sts = (AxiElmWiseProcRegRgnSts*)(baseaddr + REG_REGION_STS_OFS);
	handler->reg_region_buf_cfg = (AxiElmWiseProcRegRgnBufCfg*)(baseaddr + REG_REGION_BUF_CFG_OFS);
	handler->reg_region_fu_cfg = (AxiElmWiseProcRegRgnFuCfg*)(baseaddr + REG_REGION_FU_CFG_OFS);

	uint32_t version_encoded = handler->reg_region_prop->version;
	handler->property.version[8] = '\0';
	for(int i = 0;i < 8;i++){
		handler->property.version[i] = '0' + (version_encoded & 0x0000000F);
		version_encoded >>= 4;
	}

	uint32_t accelerator_type_encoded = handler->reg_region_prop->acc_name;
	handler->property.accelerator_type[6] = '\0';
	for(int i = 0;i < 6;i++){
		uint8_t now_c = (uint8_t)(accelerator_type_encoded & 0x0000001F);

		handler->property.accelerator_type[i] = (now_c == 26) ? '\0':('a' + now_c);
		accelerator_type_encoded >>= 5;
	}

	handler->property.accelerator_id = (uint8_t)(accelerator_type_encoded >> 30);

	handler->property.mm2s_stream_data_width = (uint16_t)(handler->reg_region_prop->info0 & 0x0000FFFF);
	handler->property.s2mm_stream_data_width = (uint16_t)((handler->reg_region_prop->info0 >> 16) & 0x0000FFFF);
	handler->property.element_wise_proc_pipeline_n = (uint8_t)(handler->reg_region_prop->info1 & 0x000000FF);

	handler->property.in_stream_width_1B_supported = (handler->reg_region_prop->info1 & (1 << 8)) ? 0x01:0x00;
	handler->property.in_stream_width_2B_supported = (handler->reg_region_prop->info1 & (1 << 9)) ? 0x01:0x00;
	handler->property.in_stream_width_4B_supported = (handler->reg_region_prop->info1 & (1 << 10)) ? 0x01:0x00;
	handler->property.out_stream_width_1B_supported = (handler->reg_region_prop->info1 & (1 << 11)) ? 0x01:0x00;
	handler->property.out_stream_width_2B_supported = (handler->reg_region_prop->info1 & (1 << 12)) ? 0x01:0x00;
	handler->property.out_stream_width_4B_supported = (handler->reg_region_prop->info1 & (1 << 13)) ? 0x01:0x00;
	handler->property.in_data_cvt_fp16_to_fp32_supported = (handler->reg_region_prop->info1 & (1 << 14)) ? 0x01:0x00;
	handler->property.in_data_cvt_int_to_fp32_supported = (handler->reg_region_prop->info1 & (1 << 15)) ? 0x01:0x00;
	handler->property.cal_fmt_s16_supported = (handler->reg_region_prop->info1 & (1 << 16)) ? 0x01:0x00;
	handler->property.cal_fmt_s32_supported = (handler->reg_region_prop->info1 & (1 << 17)) ? 0x01:0x00;
	handler->property.cal_fmt_fp32_supported = (handler->reg_region_prop->info1 & (1 << 18)) ? 0x01:0x00;
	handler->property.out_data_cvt_fp32_to_s33_supported = (handler->reg_region_prop->info1 & (1 << 19)) ? 0x01:0x00;
	handler->property.round_s33_supported = (handler->reg_region_prop->info1 & (1 << 20)) ? 0x01:0x00;
	handler->property.round_fp32_supported = (handler->reg_region_prop->info1 & (1 << 21)) ? 0x01:0x00;

	handler->reg_region_fu_cfg->fu_bypass_cfg = 0x00000000;
	handler->property.exist_in_data_cvt_unit = (handler->reg_region_fu_cfg->fu_bypass_cfg & (1 << 0)) ? 0x00:0x01;
	handler->property.exist_pow2_cell = (handler->reg_region_fu_cfg->fu_bypass_cfg & (1 << 1)) ? 0x00:0x01;
	handler->property.exist_mac_cell = (handler->reg_region_fu_cfg->fu_bypass_cfg & (1 << 2)) ? 0x00:0x01;
	handler->property.exist_out_data_cvt_unit = (handler->reg_region_fu_cfg->fu_bypass_cfg & (1 << 3)) ? 0x00:0x01;
	handler->property.exist_round_cell = (handler->reg_region_fu_cfg->fu_bypass_cfg & (1 << 4)) ? 0x00:0x01;

	handler->reg_region_ctrl->ctrl0 = (1 << 3);
	handler->property.performance_monitor_supported = (handler->reg_region_ctrl->ctrl0 & (1 << 3)) ? 0x01:0x00;
	handler->reg_region_ctrl->ctrl0 = 0x00000000;

	return 0;
}

/*************************
@ctrl
@public
@brief  使能加速器
@param  handler 通用逐元素操作处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_element_wise_proc_enable(AxiElmWiseProcHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | (1 << 0);

	return 0;
}

/*************************
@ctrl
@public
@brief  除能加速器
@param  handler 通用逐元素操作处理单元(加速器句柄)
@return none
*************************/
void axi_element_wise_proc_disable(AxiElmWiseProcHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~(1 << 0));
}

/*************************
@ctrl
@public
@brief  使能数据枢纽与处理核心
@param  handler 通用逐元素操作处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_element_wise_proc_enable_data_hub_and_proc_core(AxiElmWiseProcHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | (1 << 1) | (1 << 2);

	return 0;
}

/*************************
@ctrl
@public
@brief  除能数据枢纽与处理核心
@param  handler 通用逐元素操作处理单元(加速器句柄)
@return none
*************************/
void axi_element_wise_proc_disable_data_hub_and_proc_core(AxiElmWiseProcHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~((1 << 1) | (1 << 2)));
}

/*************************
@ctrl
@public
@brief  使能运行周期数计数器
@param  handler 通用逐元素操作处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_element_wise_proc_enable_cycle_n_cnt(AxiElmWiseProcHandler* handler){
	uint32_t pre_ctrl0;

	if(!handler->property.performance_monitor_supported){
		return -1;
	}

	pre_ctrl0 = handler->reg_region_ctrl->ctrl0;
	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | (1 << 3);

	return 0;
}

/*************************
@ctrl
@public
@brief  除能运行周期数计数器
@param  handler 通用逐元素操作处理单元(加速器句柄)
@return none
*************************/
void axi_element_wise_proc_disable_cycle_n_cnt(AxiElmWiseProcHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~(1 << 3));
}

/*************************
@ctrl
@public
@brief  启动通用逐元素操作处理单元
@param  handler 通用逐元素操作处理单元(加速器句柄)
        buf_cfg 缓存区基地址和大小配置(指针)
        use_op_a_or_b 是否使用非常量的操作数A或B
@return 是否成功
*************************/
int axi_element_wise_proc_start(AxiElmWiseProcHandler* handler, const AxiElmWiseProcBufCfg* buf_cfg, uint8_t use_op_a_or_b){
	if(handler->reg_region_ctrl->ctrl1 & 0x00000007){
		return -1;
	}

	if((handler->reg_region_ctrl->ctrl0 & 0x00000007) != 0x00000007){
		return -2;
	}

	if(
		(buf_cfg->op_x_buf_len & 0xFF000000) ||
		(use_op_a_or_b && (buf_cfg->op_a_b_buf_len & 0xFF000000)) ||
		(buf_cfg->res_buf_len & 0xFF000000)
	){
		return -3;
	}

	handler->reg_region_buf_cfg->buf_cfg0 = (uint32_t)buf_cfg->op_x_buf_baseaddr;
	handler->reg_region_buf_cfg->buf_cfg3 = buf_cfg->op_x_buf_len;

	if(use_op_a_or_b){
		handler->reg_region_buf_cfg->buf_cfg1 = (uint32_t)buf_cfg->op_a_b_buf_baseaddr;
		handler->reg_region_buf_cfg->buf_cfg4 = buf_cfg->op_a_b_buf_len;
	}

	handler->reg_region_buf_cfg->buf_cfg2 = (uint32_t)buf_cfg->res_buf_baseaddr;
	handler->reg_region_buf_cfg->buf_cfg5 = buf_cfg->res_buf_len;

	handler->reg_region_ctrl->ctrl1 =
		(1 << 0) |
		(use_op_a_or_b ? (1 << 1):0) |
		(1 << 2);

	return 0;
}

/*************************
@cfg
@public
@brief  配置通用逐元素操作处理单元
@param  handler 通用逐元素操作处理单元(加速器句柄)
        cfg 功能单元配置参数(指针)
@return 是否成功
*************************/
int axi_element_wise_proc_cfg(AxiElmWiseProcHandler* handler, const AxiElmWiseProcFuCfg* cfg){
	uint8_t use_op_a = !(cfg->is_op_a_eq_1 || cfg->is_op_a_const);

	if(
		(cfg->use_in_data_cvt_unit && (!handler->property.exist_in_data_cvt_unit)) ||
		(cfg->use_pow2_cell && (!handler->property.exist_pow2_cell)) ||
		(cfg->use_mac_cell && (!handler->property.exist_mac_cell)) ||
		(cfg->use_out_data_cvt_unit && (!handler->property.exist_out_data_cvt_unit)) ||
		(cfg->use_round_cell && (!handler->property.exist_round_cell))
	){
		return -1;
	}

	if(
		cfg->use_in_data_cvt_unit &&
		(!((cfg->in_data_fmt == ELM_INFMT_FP16) || (cfg->in_data_fmt == ELM_INFMT_FP32))) &&
		(cfg->in_fixed_point_quat_accrc >= 64)){
		return -2;
	}

	if(
		(cfg->use_pow2_cell || cfg->use_mac_cell) &&
		(cfg->cal_fmt != ELM_CALFMT_FP32) &&
		((cfg->op_x_fixed_point_quat_accrc >= 32) || (use_op_a && (cfg->op_a_fixed_point_quat_accrc >= 32)))
	){
		return -2;
	}

	if(
		cfg->use_out_data_cvt_unit &&
		(!((cfg->out_data_fmt == ELM_OUTFMT_FP16) || (cfg->out_data_fmt == ELM_OUTFMT_FP32))) &&
		(cfg->s33_cvt_fixed_point_quat_accrc >= 64)){
		return -2;
	}

	if(
		cfg->use_round_cell &&
		(!((cfg->out_data_fmt == ELM_OUTFMT_FP16) || (cfg->out_data_fmt == ELM_OUTFMT_FP32))) &&
		(
			(cfg->round_in_fixed_point_quat_accrc >= 32) ||
			(cfg->round_out_fixed_point_quat_accrc >= 32) ||
			(cfg->round_out_fixed_point_quat_accrc > cfg->round_in_fixed_point_quat_accrc)
		)
	){
		return -2;
	}

	handler->reg_region_fu_cfg->fmt_cfg =
		((uint32_t)cfg->in_data_fmt) |
		(((uint32_t)cfg->cal_fmt) << 8) |
		(((uint32_t)cfg->out_data_fmt) << 16);

	handler->reg_region_fu_cfg->fixed_point_cfg0 =
		((uint32_t)cfg->in_fixed_point_quat_accrc) |
		(((uint32_t)cfg->op_x_fixed_point_quat_accrc) << 8) |
		(((uint32_t)cfg->op_a_fixed_point_quat_accrc) << 16) |
		(((uint32_t)cfg->s33_cvt_fixed_point_quat_accrc) << 24);

	handler->reg_region_fu_cfg->fixed_point_cfg1 =
		((uint32_t)cfg->round_in_fixed_point_quat_accrc) |
		(((uint32_t)cfg->round_out_fixed_point_quat_accrc) << 8) |
		(((uint32_t)(cfg->round_in_fixed_point_quat_accrc - cfg->round_out_fixed_point_quat_accrc)) << 16);

	handler->reg_region_fu_cfg->op_a_b_cfg0 =
		((uint32_t)cfg->is_op_a_eq_1) |
		(((uint32_t)cfg->is_op_b_eq_0) << 1) |
		(((uint32_t)cfg->is_op_a_const) << 8) |
		(((uint32_t)cfg->is_op_b_const) << 9);

	if(cfg->is_op_a_const){
		handler->reg_region_fu_cfg->op_a_b_cfg1 = *(cfg->op_a_const_val_ptr);
	}

	if(cfg->is_op_b_const){
		handler->reg_region_fu_cfg->op_a_b_cfg2 = *(cfg->op_b_const_val_ptr);
	}

	handler->reg_region_fu_cfg->fu_bypass_cfg =
		(cfg->use_in_data_cvt_unit ? 0:(1 << 0)) |
		(cfg->use_pow2_cell ? 0:(1 << 1)) |
		(cfg->use_mac_cell ? 0:(1 << 2)) |
		(cfg->use_out_data_cvt_unit ? 0:(1 << 3)) |
		(cfg->use_round_cell ? 0:(1 << 4));

	return 0;
}

/*************************
@sts
@public
@brief  查询DMA命令完成数
@param  handler 通用逐元素操作处理单元(加速器句柄)
        query_type 查询类型
@return 命令完成数
*************************/
uint32_t axi_element_wise_proc_get_cmd_fns_n(AxiElmWiseProcHandler* handler, AxiElmWiseProcCmdFnsNQueryType query_type){
	switch(query_type){
	case ELM_Q_CMD_FNS_N_MM2S_0:
		return handler->reg_region_sts->sts0;
	case ELM_Q_CMD_FNS_N_MM2S_1:
		return handler->reg_region_sts->sts1;
	case ELM_Q_CMD_FNS_N_S2MM:
		return handler->reg_region_sts->sts2;
	}

	return 0xFFFFFFFF;
}

/*************************
@ctrl
@public
@brief  清除DMA命令完成数计数器
@param  handler 通用逐元素操作处理单元(加速器句柄)
        clr_type 待清除的命令完成数计数器类型
@return 是否成功
*************************/
int axi_element_wise_proc_clr_cmd_fns_n(AxiElmWiseProcHandler* handler, AxiElmWiseProcCmdFnsNClrType clr_type){
	if(clr_type == ELM_C_CMD_FNS_N_MM2S_0 || clr_type == ELM_C_ALL){
		handler->reg_region_sts->sts0 = 0;
	}

	if(clr_type == ELM_C_CMD_FNS_N_MM2S_1 || clr_type == ELM_C_ALL){
		handler->reg_region_sts->sts1 = 0;
	}

	if(clr_type == ELM_C_CMD_FNS_N_S2MM || clr_type == ELM_C_ALL){
		handler->reg_region_sts->sts2 = 0;
	}

	return 0;
}

/*************************
@sts
@public
@brief  获取性能监测计数器的值
@param  handler 通用逐元素操作处理单元(加速器句柄)
        pm_sts 性能监测状态(指针)
@return 是否成功
*************************/
int axi_element_wise_proc_get_pm_cnt(AxiElmWiseProcHandler* handler, AxiElmWiseProcPerfMonsts* pm_sts){
	if(!handler->property.performance_monitor_supported){
		return -1;
	}

	pm_sts->cycle_n = handler->reg_region_sts->sts3;

	return 0;
}

/*************************
@ctrl
@public
@brief  清除性能监测计数器
@param  handler 通用逐元素操作处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_element_wise_proc_clr_pm_cnt(AxiElmWiseProcHandler* handler){
	if(!handler->property.performance_monitor_supported){
		return -1;
	}

	handler->reg_region_sts->sts3 = 0;

	return 0;
}
