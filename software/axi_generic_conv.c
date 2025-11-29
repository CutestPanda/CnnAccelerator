/************************************************************************************************************************
通用卷积处理单元驱动
@brief  提供了通用卷积处理单元的初始化、控制、状态获取、配置等API
@date   2025/11/29
@author 陈家耀
@eidt   2025.11.29 1.00 创建了第1个正式版本
************************************************************************************************************************/

#include "axi_generic_conv.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 卷积处理单元的加速器类型编码
#define CONV_ACC_TYPE 0b110101101010101011010111000010

// 各寄存器域的偏移地址
#define REG_REGION_PROP_OFS 0x0000
#define REG_REGION_CTRL_OFS 0x0040
#define REG_REGION_STS_OFS 0x0060
#define REG_REGION_CAL_CFG_OFS 0x0080
#define REG_REGION_GRP_CONV_CFG_OFS 0x00A0
#define REG_REGION_FMAP_CFG_OFS 0x00C0
#define REG_REGION_KRN_CFG_OFS 0x0100
#define REG_REGION_BUF_CFG_OFS 0x0140

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化通用卷积处理单元
@param  handler 通用卷积处理单元(加速器句柄)
        baseaddr 加速器基地址
@return 是否成功
*************************/
int axi_generic_conv_init(AxiGnrConvHandler* handler, uint32_t baseaddr){
	uint32_t* test_ptr = (uint32_t*)baseaddr;

	if((test_ptr[1] & 0x3FFFFFFF) != CONV_ACC_TYPE){
		return -1;
	}

	handler->reg_base_ptr = (uint32_t*)baseaddr;
	handler->reg_region_prop = (AxiGnrConvRegRgnProp*)(baseaddr + REG_REGION_PROP_OFS);
	handler->reg_region_ctrl = (AxiGnrConvRegRgnCtrl*)(baseaddr + REG_REGION_CTRL_OFS);
	handler->reg_region_sts = (AxiGnrConvRegRgnSts*)(baseaddr + REG_REGION_STS_OFS);
	handler->reg_region_cal_cfg = (AxiGnrConvRegRgnCalCfg*)(baseaddr + REG_REGION_CAL_CFG_OFS);
	handler->reg_region_grp_conv_cfg = (AxiGnrConvRegRgnGrpConvCfg*)(baseaddr + REG_REGION_GRP_CONV_CFG_OFS);
	handler->reg_region_fmap_cfg = (AxiGnrConvRegRgnFmapCfg*)(baseaddr + REG_REGION_FMAP_CFG_OFS);
	handler->reg_region_kernal_cfg = (AxiGnrConvRegRgnKrnCfg*)(baseaddr + REG_REGION_KRN_CFG_OFS);
	handler->reg_region_buffer_cfg = (AxiGnrConvRegRgnBufCfg*)(baseaddr + REG_REGION_BUF_CFG_OFS);

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

	handler->property.atomic_k = (uint8_t)((handler->reg_region_prop->info0 & 0x000000FF) + 1);
	handler->property.atomic_c = (uint8_t)(((handler->reg_region_prop->info0 >> 8) & 0x000000FF) + 1);
	handler->property.max_cal_round_n = (uint8_t)(((handler->reg_region_prop->info0 >> 16) & 0x000000FF) + 1);
	handler->property.mm2s_stream_data_width = (uint16_t)((handler->reg_region_prop->info1 & 0x000000FF) + 1);
	handler->property.s2mm_stream_data_width = (uint16_t)(((handler->reg_region_prop->info1 >> 8) & 0x000000FF) + 1);
	handler->property.phy_buf_bank_n = (uint16_t)(((handler->reg_region_prop->info1 >> 16) & 0x0000FFFF) + 1);
	handler->property.phy_buf_bank_depth = (uint16_t)((handler->reg_region_prop->info2 & 0x0000FFFF) + 1);
	handler->property.max_fmbuf_row_n = (uint16_t)(((handler->reg_region_prop->info2 >> 16) & 0x0000FFFF) + 1);
	handler->property.mid_res_buf_bank_n = (uint8_t)((handler->reg_region_prop->info3 & 0x000000FF) + 1);
	handler->property.mid_res_buf_bank_depth = (uint16_t)(((handler->reg_region_prop->info3 >> 16) & 0x0000FFFF) + 1);

	handler->reg_region_cal_cfg->cal_cfg = (uint32_t)CONV_INT8;
	if((handler->reg_region_cal_cfg->cal_cfg & 0x00000007) == CONV_INT8){
		handler->property.int8_supported = 1;
	}else{
		handler->property.int8_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg = (uint32_t)CONV_INT16;
	if((handler->reg_region_cal_cfg->cal_cfg & 0x00000007) == CONV_INT16){
		handler->property.int16_supported = 1;
	}else{
		handler->property.int16_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg = (uint32_t)CONV_FP16;
	if((handler->reg_region_cal_cfg->cal_cfg & 0x00000007) == CONV_FP16){
		handler->property.fp16_supported = 1;
	}else{
		handler->property.fp16_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg = (7 << 8);
	if(((handler->reg_region_cal_cfg->cal_cfg >> 8) & 0x00000007) == 7){
		handler->property.large_v_stride_supported = 1;
	}else{
		handler->property.large_v_stride_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg = (7 << 11);
	if(((handler->reg_region_cal_cfg->cal_cfg >> 11) & 0x00000007) == 7){
		handler->property.large_h_stride_supported = 1;
	}else{
		handler->property.large_h_stride_supported = 0;
	}

	handler->reg_region_grp_conv_cfg->grp_conv0 = 0x00000001;
	if(handler->reg_region_grp_conv_cfg->grp_conv0 & 0x00000001){
		handler->property.group_conv_supported = 1;
	}else{
		handler->property.group_conv_supported = 0;
	}

	handler->reg_region_fmap_cfg->fmap_cfg4 = 7;
	if((handler->reg_region_fmap_cfg->fmap_cfg4 & 0x00000007) == 7){
		handler->property.ext_padding_supported = 1;
	}else{
		handler->property.ext_padding_supported = 0;
	}

	handler->reg_region_fmap_cfg->fmap_cfg4 = (7 << 6);
	if(((handler->reg_region_fmap_cfg->fmap_cfg4 >> 6) & 0x00000007) == 7){
		handler->property.inner_padding_supported = 1;
	}else{
		handler->property.inner_padding_supported = 0;
	}

	handler->reg_region_kernal_cfg->krn_cfg1 = (15 << 4);
	if(((handler->reg_region_kernal_cfg->krn_cfg1 >> 4) & 0x0000000F) == 15){
		handler->property.kernal_dilation_supported = 1;
	}else{
		handler->property.kernal_dilation_supported = 0;
	}

	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;
	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | 0x00000002;
	if(handler->reg_region_ctrl->ctrl0 & 0x00000002){
		handler->property.performance_monitor_supported = 1;
	}else{
		handler->property.performance_monitor_supported = 0;
	}
	handler->reg_region_ctrl->ctrl0 = pre_ctrl0;

	axi_generic_conv_disable_cal_sub_sys(handler);

	return 0;
}

/*************************
@ctrl
@public
@brief  使能计算子系统
@param  handler 通用卷积处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_generic_conv_enable_cal_sub_sys(AxiGnrConvHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | 0x00000001;

	return 0;
}

/*************************
@ctrl
@public
@brief  除能计算子系统
@param  handler 通用卷积处理单元(加速器句柄)
@return none
*************************/
void axi_generic_conv_disable_cal_sub_sys(AxiGnrConvHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~0x00000001);
}

/*************************
@ctrl
@public
@brief  使能性能监测计数器
@param  handler 通用卷积处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_generic_conv_enable_pm_cnt(AxiGnrConvHandler* handler){
	if(!handler->property.performance_monitor_supported){
		return -1;
	}

	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | 0x00000002;

	return 0;
}

/*************************
@ctrl
@public
@brief  除能性能监测计数器
@param  handler 通用卷积处理单元(加速器句柄)
@return none
*************************/
void axi_generic_conv_disable_pm_cnt(AxiGnrConvHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~0x00000002);
}

/*************************
@ctrl
@public
@brief  启动通用卷积处理单元
@param  handler 通用卷积处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_generic_conv_start(AxiGnrConvHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	if(!(pre_ctrl0 & 0x00000001)){
		return -1;
	}

	if(axi_generic_conv_is_busy(handler)){
		return -2;
	}

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | 0x00000700;

	return 0;
}

/*************************
@sts
@public
@brief  判断通用卷积处理单元是否忙碌
@param  handler 通用卷积处理单元(加速器句柄)
@return 是否忙碌
*************************/
uint8_t axi_generic_conv_is_busy(AxiGnrConvHandler* handler){
	// 注意: 仅仅检查"请求生成单元是否空闲"是不够的!
	if((handler->reg_region_sts->sts0 & 0x00000007) != 0x00000007){
		return 1;
	}

	return 0;
}

/*************************
@ctrl
@public
@brief  配置通用卷积处理单元
@param  handler 通用卷积处理单元(加速器句柄)
        cfg 配置参数(句柄)
@return 是否成功
*************************/
int axi_generic_conv_cfg(AxiGnrConvHandler* handler, const AxiGnrConvCfg* cfg){
	if(axi_generic_conv_is_busy(handler)){
		return -1;
	}

	if((cfg->cal_cfg.cal_fmt == CONV_INT8 && (!handler->property.int8_supported)) ||
		(cfg->cal_cfg.cal_fmt == CONV_INT16 && (!handler->property.int16_supported)) ||
		(cfg->cal_cfg.cal_fmt == CONV_FP16 && (!handler->property.fp16_supported))){
		return -2;
	}

	if(cfg->cal_cfg.conv_vertical_stride > 8 || cfg->cal_cfg.conv_vertical_stride == 0 ||
		(cfg->cal_cfg.conv_vertical_stride > 1 && (!handler->property.large_v_stride_supported))){
		return -2;
	}

	if(cfg->cal_cfg.conv_horizontal_stride > 8 || cfg->cal_cfg.conv_horizontal_stride == 0 ||
		(cfg->cal_cfg.conv_horizontal_stride > 1 && (!handler->property.large_h_stride_supported))){
		return -2;
	}

	if(cfg->cal_cfg.cal_round_n > 16 || cfg->cal_cfg.cal_round_n == 0 ||
		cfg->cal_cfg.cal_round_n > handler->property.max_cal_round_n){
		return -2;
	}

	if(cfg->group_n == 0 ||
		(cfg->fmap_cfg.ifmap_chn_n % cfg->group_n) ||
		(cfg->group_n > 1 && ((!handler->property.group_conv_supported) || (cfg->kernal_cfg.kernal_chn_n != cfg->kernal_cfg.kernal_n)))){
		return -2;
	}

	if(cfg->fmap_cfg.external_padding_left > 7 || (cfg->fmap_cfg.external_padding_left > 0 && (!handler->property.ext_padding_supported))){
		return -2;
	}
	if(cfg->fmap_cfg.external_padding_right > 7 || (cfg->fmap_cfg.external_padding_right > 0 && (!handler->property.ext_padding_supported))){
		return -2;
	}
	if(cfg->fmap_cfg.external_padding_top > 7 || (cfg->fmap_cfg.external_padding_top > 0 && (!handler->property.ext_padding_supported))){
		return -2;
	}
	if(cfg->fmap_cfg.external_padding_bottom > 7 || (cfg->fmap_cfg.external_padding_bottom > 0 && (!handler->property.ext_padding_supported))){
		return -2;
	}
	if(cfg->fmap_cfg.inner_padding_left_right > 7 || (cfg->fmap_cfg.inner_padding_left_right > 0 && (!handler->property.inner_padding_supported))){
		return -2;
	}
	if(cfg->fmap_cfg.inner_padding_top_bottom > 7 || (cfg->fmap_cfg.inner_padding_top_bottom > 0 && (!handler->property.inner_padding_supported))){
		return -2;
	}

	if(cfg->kernal_cfg.dilation_n > 15 || (cfg->kernal_cfg.dilation_n > 0 && (!handler->property.kernal_dilation_supported))){
		return -2;
	}

	if(cfg->fmap_cfg.ifmap_chn_n != cfg->kernal_cfg.kernal_chn_n){
		return -2;
	}

	if(cfg->buffer_cfg.fmbufbankn == 0 || cfg->buffer_cfg.fmbufbankn >= handler->property.phy_buf_bank_n - 1){
		return -2;
	}

	uint32_t ifmap_size = cfg->fmap_cfg.ifmap_width * cfg->fmap_cfg.ifmap_height;
	uint32_t n_foreach_group = cfg->fmap_cfg.ifmap_chn_n / cfg->group_n;
	uint32_t data_size_foreach_group = ifmap_size * n_foreach_group * (cfg->cal_cfg.cal_fmt == CONV_INT8 ? 1:2);
	uint32_t fmap_ext_i_bottom =
		((uint32_t)cfg->fmap_cfg.ifmap_height) + ((uint32_t)cfg->fmap_cfg.external_padding_top) +
		((uint32_t)(cfg->fmap_cfg.ifmap_height - 1)) * ((uint32_t)cfg->fmap_cfg.inner_padding_top_bottom) - 1;

	uint32_t kernal_len;

	switch(cfg->kernal_cfg.kernal_shape){
	case CONV_KRN_1x1: kernal_len = 1;break;
	case CONV_KRN_3x3: kernal_len = 3;break;
	case CONV_KRN_5x5: kernal_len = 5;break;
	case CONV_KRN_7x7: kernal_len = 7;break;
	case CONV_KRN_9x9: kernal_len = 9;break;
	case CONV_KRN_11x11: kernal_len = 11;break;
	}

	uint32_t dilated_kernal_len = kernal_len + (kernal_len - 1) * ((uint32_t)cfg->kernal_cfg.dilation_n);
	uint32_t c_foreach_set = (cfg->group_n > 1) ? n_foreach_group:cfg->kernal_cfg.kernal_chn_n;
	uint32_t cgrpn_foreach_kernal_set =
		(c_foreach_set / handler->property.atomic_c) +
		(c_foreach_set % handler->property.atomic_c ? 1:0);
	uint32_t kernal_set_n =
		(cfg->group_n > 1) ?
			cfg->group_n:
			(
				(cfg->kernal_cfg.kernal_n / cfg->max_wgtblk_w) +
				(cfg->kernal_cfg.kernal_n % cfg->max_wgtblk_w ? 1:0)
			);

	uint32_t ext_fmap_w =
		((uint32_t)cfg->fmap_cfg.ifmap_width) +
		((uint32_t)cfg->fmap_cfg.external_padding_left) + ((uint32_t)cfg->fmap_cfg.external_padding_right) +
		((uint32_t)(cfg->fmap_cfg.ifmap_width - 1)) * ((uint32_t)cfg->fmap_cfg.inner_padding_left_right);
	uint32_t ext_fmap_h = fmap_ext_i_bottom + 1 + ((uint32_t)cfg->fmap_cfg.external_padding_bottom);
	uint32_t ofmap_width;
	uint32_t ofmap_height;

	uint32_t fmbufrown = ((uint32_t)cfg->buffer_cfg.fmbufbankn) * ((uint32_t)handler->property.phy_buf_bank_depth);

	switch(cfg->buffer_cfg.fmbufcoln){
	case CONV_COLN_4: fmbufrown >>= 2;break;
	case CONV_COLN_8: fmbufrown >>= 3;break;
	case CONV_COLN_16: fmbufrown >>= 4;break;
	case CONV_COLN_32: fmbufrown >>= 5;break;
	case CONV_COLN_64: fmbufrown >>= 6;break;
	case CONV_COLN_128: fmbufrown >>= 7;break;
	case CONV_COLN_256: fmbufrown >>= 8;break;
	case CONV_COLN_512: fmbufrown >>= 9;break;
	case CONV_COLN_1024: fmbufrown >>= 10;break;
	case CONV_COLN_2048: fmbufrown >>= 11;break;
	case CONV_COLN_4096: fmbufrown >>= 12;break;
	}

	if(fmbufrown > 1024){
		fmbufrown = 1024;
	}

	uint32_t kbufgrpn =
		((uint32_t)(handler->property.phy_buf_bank_n - cfg->buffer_cfg.fmbufbankn)) * ((uint32_t)handler->property.phy_buf_bank_depth) /
		(kernal_len * kernal_len);

	switch(cfg->buffer_cfg.sfc_n_each_wgtblk){
	case CONV_WGTBLK_SFC_N_1: break;
	case CONV_WGTBLK_SFC_N_2: kbufgrpn >>= 1;break;
	case CONV_WGTBLK_SFC_N_4: kbufgrpn >>= 2;break;
	case CONV_WGTBLK_SFC_N_8: kbufgrpn >>= 3;break;
	case CONV_WGTBLK_SFC_N_16: kbufgrpn >>= 4;break;
	case CONV_WGTBLK_SFC_N_32: kbufgrpn >>= 5;break;
	case CONV_WGTBLK_SFC_N_64: kbufgrpn >>= 6;break;
	case CONV_WGTBLK_SFC_N_128: kbufgrpn >>= 7;break;
	}

	if(kbufgrpn > 256){
		kbufgrpn = 256;
	}

	if((ext_fmap_w - dilated_kernal_len) % cfg->cal_cfg.conv_horizontal_stride){
		return -2;
	}else{
		ofmap_width = (ext_fmap_w - dilated_kernal_len) / cfg->cal_cfg.conv_horizontal_stride + 1;
	}

	if((ext_fmap_h - dilated_kernal_len) % cfg->cal_cfg.conv_vertical_stride){
		return -2;
	}else{
		ofmap_height = (ext_fmap_h - dilated_kernal_len) / cfg->cal_cfg.conv_vertical_stride + 1;
	}

	uint32_t mid_res_item_n_foreach_row = ((uint32_t)cfg->cal_cfg.cal_round_n) * ofmap_width;
	uint32_t bank_n_foreach_mid_res_row =
		mid_res_item_n_foreach_row / handler->property.mid_res_buf_bank_depth +
		(mid_res_item_n_foreach_row % handler->property.mid_res_buf_bank_depth ? 1:0);
	uint32_t mid_res_buf_row_n_bufferable = handler->property.mid_res_buf_bank_n / bank_n_foreach_mid_res_row;

	if(mid_res_buf_row_n_bufferable > 16){
		mid_res_buf_row_n_bufferable = 16;
	}

	handler->reg_region_cal_cfg->cal_cfg =
		((uint32_t)cfg->cal_cfg.cal_fmt) |
		(((uint32_t)(cfg->cal_cfg.conv_vertical_stride - 1)) << 8) |
		(((uint32_t)(cfg->cal_cfg.conv_horizontal_stride - 1)) << 11) |
		(((uint32_t)(cfg->cal_cfg.cal_round_n - 1)) << 16);

	handler->reg_region_grp_conv_cfg->grp_conv0 = (cfg->group_n > 1 ? 0x00000001:0x00000000) | (data_size_foreach_group << 1);
	handler->reg_region_grp_conv_cfg->grp_conv1 = (n_foreach_group - 1) | (((uint32_t)cfg->group_n - 1) << 16);

	handler->reg_region_fmap_cfg->fmap_cfg0 = (uint32_t)cfg->ifmap_baseaddr;
	handler->reg_region_fmap_cfg->fmap_cfg1 = (uint32_t)cfg->ofmap_baseaddr;
	handler->reg_region_fmap_cfg->fmap_cfg2 = ((uint32_t)(cfg->fmap_cfg.ifmap_width - 1)) | (((uint32_t)(cfg->fmap_cfg.ifmap_chn_n - 1)) << 16);
	handler->reg_region_fmap_cfg->fmap_cfg3 = ifmap_size - 1;
	handler->reg_region_fmap_cfg->fmap_cfg4 =
		((uint32_t)cfg->fmap_cfg.external_padding_left) |
		(((uint32_t)cfg->fmap_cfg.external_padding_top) << 3) |
		(((uint32_t)cfg->fmap_cfg.inner_padding_left_right) << 6) |
		(((uint32_t)cfg->fmap_cfg.inner_padding_top_bottom) << 9) |
		(fmap_ext_i_bottom << 16);
	handler->reg_region_fmap_cfg->fmap_cfg5 = ((uint32_t)cfg->fmap_cfg.ofmap_data_type) | ((ofmap_width - 1) << 2) | ((ofmap_height - 1) << 17);

	handler->reg_region_kernal_cfg->krn_cfg0 = (uint32_t)cfg->kernal_wgt_baseaddr;
	handler->reg_region_kernal_cfg->krn_cfg1 =
		((uint32_t)cfg->kernal_cfg.kernal_shape) |
		(((uint32_t)cfg->kernal_cfg.dilation_n) << 4) |
		((dilated_kernal_len - 1) << 8) |
		((cgrpn_foreach_kernal_set - 1) << 16);
	handler->reg_region_kernal_cfg->krn_cfg2 = ((uint32_t)(cfg->kernal_cfg.kernal_n - 1)) | ((kernal_set_n - 1) << 16);
	handler->reg_region_kernal_cfg->krn_cfg3 = cfg->max_wgtblk_w;

	handler->reg_region_buffer_cfg->buf_cfg0 = (uint32_t)cfg->buffer_cfg.fmbufbankn;
	handler->reg_region_buffer_cfg->buf_cfg1 = ((uint32_t)cfg->buffer_cfg.fmbufcoln) | ((fmbufrown - 1) << 16);
	handler->reg_region_buffer_cfg->buf_cfg2 = ((uint32_t)cfg->buffer_cfg.sfc_n_each_wgtblk) | ((kbufgrpn - 1) << 8);
	handler->reg_region_buffer_cfg->buf_cfg3 = (mid_res_item_n_foreach_row - 1) | ((mid_res_buf_row_n_bufferable - 1) << 16);

	return 0;
}

/*************************
@sts
@public
@brief  查询DMA命令完成数
@param  handler 通用卷积处理单元(加速器句柄)
        query_type 查询类型
@return 命令完成数
*************************/
uint32_t axi_generic_conv_get_cmd_fns_n(AxiGnrConvHandler* handler, AxiGnrConvCmdFnsNQueryType query_type){
	switch(query_type){
	case Q_CMD_FNS_N_MM2S_0:
		return handler->reg_region_sts->sts1;
	case Q_CMD_FNS_N_MM2S_1:
		return handler->reg_region_sts->sts2;
	case Q_CMD_FNS_N_S2MM:
		return handler->reg_region_sts->sts3;
	}

	return 0xFFFFFFFF;
}

/*************************
@ctrl
@public
@brief  清除DMA命令完成数计数器
@param  handler 通用卷积处理单元(加速器句柄)
        clr_type 待清除的命令完成数计数器类型
@return 是否成功
*************************/
int axi_generic_conv_clr_cmd_fns_n(AxiGnrConvHandler* handler, AxiGnrConvCmdFnsNClrType clr_type){
	if(clr_type == C_CMD_FNS_N_MM2S_0 || clr_type == C_ALL){
		handler->reg_region_sts->sts1 = 0;
	}

	if(clr_type == C_CMD_FNS_N_MM2S_1 || clr_type == C_ALL){
		handler->reg_region_sts->sts2 = 0;
	}

	if(clr_type == C_CMD_FNS_N_S2MM || clr_type == C_ALL){
		handler->reg_region_sts->sts3 = 0;
	}

	return 0;
}

/*************************
@sts
@public
@brief  获取性能监测计数器的值
@param  handler 通用卷积处理单元(加速器句柄)
@return 性能监测计数器的值
*************************/
uint32_t axi_generic_conv_get_pm_cnt(AxiGnrConvHandler* handler){
	return handler->reg_region_sts->sts4;
}

/*************************
@ctrl
@public
@brief  清除性能监测计数器
@param  handler 通用卷积处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_generic_conv_clr_pm_cnt(AxiGnrConvHandler* handler){
	if(!handler->property.performance_monitor_supported){
		return -1;
	}

	handler->reg_region_sts->sts4 = 0;

	return 0;
}
