/************************************************************************************************************************
通用池化处理单元驱动
@brief  提供了通用池化处理单元的初始化、控制、状态获取、配置等API
               配置分为池化和上采样模式
@date   2025/12/17
@author 陈家耀
@eidt   2025.12.17 1.00 创建了第1个正式版本
************************************************************************************************************************/

#include "axi_generic_pool.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

// 池化处理单元的加速器类型编码
#define POOL_ACC_TYPE 0b110101101001011011100111001111

// 各寄存器域的偏移地址
#define REG_REGION_PROP_OFS 0x0000
#define REG_REGION_CTRL_OFS 0x0040
#define REG_REGION_STS_OFS 0x0060
#define REG_REGION_CAL_CFG_OFS 0x0080
#define REG_REGION_FMAP_CFG_OFS 0x00C0
#define REG_REGION_BUF_CFG_OFS 0x0100

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化通用池化处理单元
@param  handler 通用池化处理单元(加速器句柄)
        baseaddr 加速器基地址
@return 是否成功
*************************/
int axi_generic_pool_init(AxiGnrPoolHandler* handler, uint32_t baseaddr){
	uint32_t* test_ptr = (uint32_t*)baseaddr;

	if((test_ptr[1] & 0x3FFFFFFF) != POOL_ACC_TYPE){
		return -1;
	}

	handler->reg_base_ptr = (uint32_t*)baseaddr;
	handler->reg_region_prop = (AxiGnrPoolRegRgnProp*)(baseaddr + REG_REGION_PROP_OFS);
	handler->reg_region_ctrl = (AxiGnrPoolRegRgnCtrl*)(baseaddr + REG_REGION_CTRL_OFS);
	handler->reg_region_sts = (AxiGnrPoolRegRgnSts*)(baseaddr + REG_REGION_STS_OFS);
	handler->reg_region_cal_cfg = (AxiGnrPoolRegRgnCalCfg*)(baseaddr + REG_REGION_CAL_CFG_OFS);
	handler->reg_region_fmap_cfg = (AxiGnrPoolRegRgnFmapCfg*)(baseaddr + REG_REGION_FMAP_CFG_OFS);
	handler->reg_region_buffer_cfg = (AxiGnrPoolRegRgnBufCfg*)(baseaddr + REG_REGION_BUF_CFG_OFS);

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

	handler->property.atomic_c = (uint8_t)(handler->reg_region_prop->info0 & 0x000000FF);
	handler->property.post_mac_prl_n = (uint8_t)((handler->reg_region_prop->info0 >> 8) & 0x000000FF);
	handler->property.max_fmbuf_row_n = (uint16_t)((handler->reg_region_prop->info0 >> 16) & 0x0000FFFF);
	handler->property.mm2s_stream_data_width = (uint16_t)(handler->reg_region_prop->info1 & 0x0000FFFF);
	handler->property.s2mm_stream_data_width = (uint16_t)((handler->reg_region_prop->info1 >> 16) & 0x0000FFFF);
	handler->property.phy_buf_bank_n = (uint16_t)(handler->reg_region_prop->info2 & 0x0000FFFF);
	handler->property.phy_buf_bank_depth = (uint16_t)((handler->reg_region_prop->info2 >> 16) & 0x0000FFFF);
	handler->property.mid_res_buf_bank_n = (uint16_t)(handler->reg_region_prop->info3 & 0x0000FFFF);
	handler->property.mid_res_buf_bank_depth = (uint16_t)((handler->reg_region_prop->info3 >> 16) & 0x0000FFFF);

	handler->reg_region_cal_cfg->cal_cfg0 = (uint32_t)PROC_MODE_AVG;
	if((handler->reg_region_cal_cfg->cal_cfg0 & 0x0000000F) == PROC_MODE_AVG){
		handler->property.avg_pool_supported = 1;
	}else{
		handler->property.avg_pool_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg0 = (uint32_t)PROC_MODE_MAX;
	if((handler->reg_region_cal_cfg->cal_cfg0 & 0x0000000F) == PROC_MODE_MAX){
		handler->property.max_pool_supported = 1;
	}else{
		handler->property.max_pool_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg0 = (uint32_t)PROC_MODE_UPSP;
	if((handler->reg_region_cal_cfg->cal_cfg0 & 0x0000000F) == PROC_MODE_UPSP){
		handler->property.up_sample_supported = 1;
	}else{
		handler->property.up_sample_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg0 = (((uint32_t)POOL_INT8) << 4);
	if(((handler->reg_region_cal_cfg->cal_cfg0 >> 4) & 0x0000000F) == POOL_INT8){
		handler->property.int8_supported = 1;
	}else{
		handler->property.int8_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg0 = (((uint32_t)POOL_INT16) << 4);
	if(((handler->reg_region_cal_cfg->cal_cfg0 >> 4) & 0x0000000F) == POOL_INT16){
		handler->property.int16_supported = 1;
	}else{
		handler->property.int16_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg0 = (((uint32_t)POOL_FP16) << 4);
	if(((handler->reg_region_cal_cfg->cal_cfg0 >> 4) & 0x0000000F) == POOL_FP16){
		handler->property.fp16_supported = 1;
	}else{
		handler->property.fp16_supported = 0;
	}

	if(((handler->reg_region_prop->info0 >> 8) & 0x000000FF) != 0x00){
		handler->property.post_mac_supported = 1;
	}else{
		handler->property.post_mac_supported = 0;
	}

	handler->reg_region_fmap_cfg->fmap_cfg4 = 0x01010000;
	if(handler->reg_region_fmap_cfg->fmap_cfg4 == 0x01010000){
		handler->property.ext_padding_supported = 1;
	}else{
		handler->property.ext_padding_supported = 0;
	}

	handler->reg_region_cal_cfg->cal_cfg2 = 0x00000001;
	if(handler->reg_region_cal_cfg->cal_cfg2 == 0x00000001){
		handler->property.non_zero_const_padding_supported = 1;
	}else{
		handler->property.non_zero_const_padding_supported = 0;
	}

	handler->reg_region_ctrl->ctrl0 = (0x00000001 << 10);
	if(handler->reg_region_ctrl->ctrl0 & (0x00000001 << 10)){
		handler->property.performance_monitor_supported = 1;
	}else{
		handler->property.performance_monitor_supported = 0;
	}
	handler->reg_region_ctrl->ctrl0 = 0x00000000;

	return 0;
}

/*************************
@ctrl
@public
@brief  使能计算子系统
@param  handler 通用池化处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_generic_pool_enable_cal_sub_sys(AxiGnrPoolHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | (0x00000001 << 8);

	return 0;
}

/*************************
@ctrl
@public
@brief  除能计算子系统
@param  handler 通用池化处理单元(加速器句柄)
@return none
*************************/
void axi_generic_pool_disable_cal_sub_sys(AxiGnrPoolHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~(0x00000001 << 8));
}

/*************************
@ctrl
@public
@brief  使能性能监测计数器
@param  handler 通用池化处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_generic_pool_enable_pm_cnt(AxiGnrPoolHandler* handler){
	if(!handler->property.performance_monitor_supported){
		return -1;
	}

	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | (0x00000001 << 10);

	return 0;
}

/*************************
@ctrl
@public
@brief  除能性能监测计数器
@param  handler 通用池化处理单元(加速器句柄)
@return none
*************************/
void axi_generic_pool_disable_pm_cnt(AxiGnrPoolHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~(0x00000001 << 10));
}

/*************************
@ctrl
@public
@brief  启动通用池化处理单元
@param  handler 通用池化处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_generic_pool_start(AxiGnrPoolHandler* handler){
	uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

	if(!(pre_ctrl0 & (0x00000001 << 8))){
		return -1;
	}

	if(axi_generic_pool_is_busy(handler)){
		return -2;
	}

	handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | 0x00000003;

	return 0;
}

/*************************
@sts
@public
@brief  判断通用池化处理单元是否忙碌
@param  handler 通用池化处理单元(加速器句柄)
@return 是否忙碌
*************************/
uint8_t axi_generic_pool_is_busy(AxiGnrPoolHandler* handler){
	// 注意: 仅仅检查"请求生成单元是否空闲"是不够的!
	if((handler->reg_region_sts->sts0 & 0x00000003) != 0x00000003){
		return 1;
	}

	return 0;
}

/*************************
@cfg
@public
@brief  以池化模式配置通用池化处理单元
@param  handler 通用池化处理单元(加速器句柄)
		mode 池化模式
        fmap_cfg 特征图配置参数(句柄)
        buffer_cfg 缓存配置参数(句柄)
        cal_cfg 池化处理配置参数(句柄)
@return 是否成功
*************************/
int axi_generic_pool_cfg_in_pool_mode(
	AxiGnrPoolHandler* handler,
	AxiGnrPoolProcMode mode,
	const AxiGnrPoolFmapCfg* fmap_cfg, const AxiGnrPoolBufferCfg* buffer_cfg, const AxiGnrPoolPoolModeCfg* cal_cfg
){
	uint32_t ifmap_size; // 输入特征图大小
	uint16_t ext_fmap_w; // 扩展特征图宽度
	uint16_t ext_fmap_h; // 扩展特征图高度
	uint16_t ofmap_w; // 输出特征图宽度
	uint16_t ofmap_h; // 输出特征图高度
	uint32_t fmbuf_row_n; // 特征图缓存可缓存的表面行数
	uint16_t bank_n_foreach_mid_res_row; // 每个中间结果行所占用的BANK数
	uint16_t mid_res_buf_row_n_bufferable; // 中间结果缓存可缓存的行数

	ifmap_size = ((uint32_t)fmap_cfg->ifmap_w) * ((uint32_t)fmap_cfg->ifmap_h);
	ext_fmap_w = fmap_cfg->ifmap_w + (uint16_t)fmap_cfg->external_padding_left + (uint16_t)fmap_cfg->external_padding_right;
	ext_fmap_h = fmap_cfg->ifmap_h + (uint16_t)fmap_cfg->external_padding_top + (uint16_t)fmap_cfg->external_padding_bottom;

	if((ext_fmap_w - cal_cfg->pool_window_w) % cal_cfg->horizontal_stride){
		ofmap_w = 0;

		return -1;
	}else{
		ofmap_w = (ext_fmap_w - cal_cfg->pool_window_w) / cal_cfg->horizontal_stride + 1;
	}

	if((ext_fmap_h - cal_cfg->pool_window_h) % cal_cfg->vertical_stride){
		ofmap_h = 0;

		return -1;
	}else{
		ofmap_h = (ext_fmap_h - cal_cfg->pool_window_h) / cal_cfg->vertical_stride + 1;
	}

	if(cal_cfg->horizontal_stride > 8 || cal_cfg->vertical_stride > 8){
		return -1;
	}

	if(fmap_cfg->external_padding_left > 7 || fmap_cfg->external_padding_top > 7){
		return -1;
	}

	fmbuf_row_n = ((uint32_t)handler->property.phy_buf_bank_n) * ((uint32_t)handler->property.phy_buf_bank_depth);

	switch(buffer_cfg->fmbufcoln){
	case POOL_COLN_4: fmbuf_row_n >>= 2;break;
	case POOL_COLN_8: fmbuf_row_n >>= 3;break;
	case POOL_COLN_16: fmbuf_row_n >>= 4;break;
	case POOL_COLN_32: fmbuf_row_n >>= 5;break;
	case POOL_COLN_64: fmbuf_row_n >>= 6;break;
	case POOL_COLN_128: fmbuf_row_n >>= 7;break;
	case POOL_COLN_256: fmbuf_row_n >>= 8;break;
	case POOL_COLN_512: fmbuf_row_n >>= 9;break;
	case POOL_COLN_1024: fmbuf_row_n >>= 10;break;
	case POOL_COLN_2048: fmbuf_row_n >>= 11;break;
	case POOL_COLN_4096: fmbuf_row_n >>= 12;break;
	}

	if(fmbuf_row_n > (uint32_t)handler->property.max_fmbuf_row_n){
		fmbuf_row_n = (uint32_t)handler->property.max_fmbuf_row_n;
	}

	bank_n_foreach_mid_res_row =
		ofmap_w / handler->property.mid_res_buf_bank_depth +
		(ofmap_w % handler->property.mid_res_buf_bank_depth ? 1:0);
	mid_res_buf_row_n_bufferable =
		handler->property.mid_res_buf_bank_n / bank_n_foreach_mid_res_row;

	if(!(mode == PROC_MODE_AVG || mode == PROC_MODE_MAX)){
		return -1;
	}

	if((mode == PROC_MODE_AVG && (!handler->property.avg_pool_supported)) || (mode == PROC_MODE_MAX && (!handler->property.max_pool_supported))){
		return -2;
	}

	if(
		(cal_cfg->cal_fmt == POOL_INT8 && (!handler->property.int8_supported)) ||
		(cal_cfg->cal_fmt == POOL_INT16 && (!handler->property.int16_supported)) ||
		(cal_cfg->cal_fmt == POOL_FP16 && (!handler->property.fp16_supported))
	){
		return -2;
	}

	if(cal_cfg->use_post_mac && (!handler->property.post_mac_supported)){
		return -2;
	}

	if(
		(fmap_cfg->external_padding_left || fmap_cfg->external_padding_right || fmap_cfg->external_padding_top || fmap_cfg->external_padding_bottom) &&
		(!handler->property.ext_padding_supported)
	){
		return -2;
	}

	handler->reg_region_cal_cfg->cal_cfg0 =
		(((uint32_t)mode) << 0) |
		(((uint32_t)cal_cfg->cal_fmt) << 4) |
		(((uint32_t)(cal_cfg->horizontal_stride - 1)) << 8) |
		(((uint32_t)(cal_cfg->vertical_stride - 1)) << 16);
	handler->reg_region_cal_cfg->cal_cfg1 =
		(((uint32_t)(cal_cfg->pool_window_w - 1)) << 0) |
		(((uint32_t)(cal_cfg->pool_window_h - 1)) << 8);
	handler->reg_region_cal_cfg->cal_cfg2 = 0x00000000;

	if(cal_cfg->use_post_mac){
		uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

		handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | (0x00000001 << 9);

		handler->reg_region_cal_cfg->cal_cfg3 =
			(((uint32_t)cal_cfg->post_mac_is_a_eq_1) << 0) |
			(((uint32_t)cal_cfg->post_mac_is_b_eq_0) << 1) |
			(((uint32_t)cal_cfg->post_mac_fixed_point_quat_accrc) << 8);
		handler->reg_region_cal_cfg->cal_cfg4 =
			(uint32_t)cal_cfg->post_mac_param_a;
		handler->reg_region_cal_cfg->cal_cfg5 =
			(uint32_t)cal_cfg->post_mac_param_b;
	}else{
		uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

		handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~(0x00000001 << 9));
	}

	handler->reg_region_fmap_cfg->fmap_cfg0 =
		(uint32_t)fmap_cfg->ifmap_baseaddr;
	handler->reg_region_fmap_cfg->fmap_cfg1 =
		(uint32_t)fmap_cfg->ofmap_baseaddr;
	handler->reg_region_fmap_cfg->fmap_cfg2 =
		(((uint32_t)(fmap_cfg->ifmap_w - 1)) << 0) |
		(((uint32_t)(fmap_cfg->ifmap_h - 1)) << 16);
	handler->reg_region_fmap_cfg->fmap_cfg3 =
		ifmap_size - 1;
	handler->reg_region_fmap_cfg->fmap_cfg4 =
		(((uint32_t)(fmap_cfg->ifmap_c - 1)) << 0) |
		(((uint32_t)fmap_cfg->external_padding_left) << 16) |
		(((uint32_t)fmap_cfg->external_padding_top) << 24);
	handler->reg_region_fmap_cfg->fmap_cfg5 =
		(((uint32_t)(ext_fmap_w - 1)) << 0) |
		(((uint32_t)(ext_fmap_h - 1)) << 16);
	handler->reg_region_fmap_cfg->fmap_cfg6 =
		(((uint32_t)(ofmap_w - 1)) << 0) |
		(((uint32_t)(ofmap_h - 1)) << 15) |
		(((uint32_t)fmap_cfg->ofmap_data_type) << 30);

	handler->reg_region_buffer_cfg->buf_cfg0 =
		(((uint32_t)(buffer_cfg->fmbufcoln)) << 0) |
		(((uint32_t)fmbuf_row_n) << 16);
	handler->reg_region_buffer_cfg->buf_cfg1 =
		(uint32_t)(mid_res_buf_row_n_bufferable - 1);

	return 0;
}

/*************************
@cfg
@public
@brief  以上采样模式配置通用池化处理单元
@param  handler 通用池化处理单元(加速器句柄)
        fmap_cfg 特征图配置参数(句柄)
        buffer_cfg 缓存配置参数(句柄)
        cal_cfg 上采样处理配置参数(句柄)
@return 是否成功
*************************/
int axi_generic_pool_cfg_in_up_sample_mode(
	AxiGnrPoolHandler* handler,
	const AxiGnrPoolFmapCfg* fmap_cfg, const AxiGnrPoolBufferCfg* buffer_cfg, const AxiGnrPoolUpsModeCfg* cal_cfg
){
	uint32_t ifmap_size; // 输入特征图大小
	uint16_t ext_fmap_w; // 扩展特征图宽度
	uint16_t ext_fmap_h; // 扩展特征图高度
	uint16_t ofmap_w; // 输出特征图宽度
	uint16_t ofmap_h; // 输出特征图高度
	uint32_t fmbuf_row_n; // 特征图缓存可缓存的表面行数
	uint16_t bank_n_foreach_mid_res_row; // 每个中间结果行所占用的BANK数
	uint16_t mid_res_buf_row_n_bufferable; // 中间结果缓存可缓存的行数

	ifmap_size = ((uint32_t)fmap_cfg->ifmap_w) * ((uint32_t)fmap_cfg->ifmap_h);
	ext_fmap_w = fmap_cfg->ifmap_w + (uint16_t)fmap_cfg->external_padding_left + (uint16_t)fmap_cfg->external_padding_right;
	ext_fmap_h = fmap_cfg->ifmap_h + (uint16_t)fmap_cfg->external_padding_top + (uint16_t)fmap_cfg->external_padding_bottom;
	ofmap_w = ext_fmap_w * cal_cfg->upsample_horizontal_n;
	ofmap_h = ext_fmap_h * cal_cfg->upsample_vertical_n;

	if(fmap_cfg->external_padding_left > 7 || fmap_cfg->external_padding_top > 7){
		return -1;
	}

	fmbuf_row_n = ((uint32_t)handler->property.phy_buf_bank_n) * ((uint32_t)handler->property.phy_buf_bank_depth);

	switch(buffer_cfg->fmbufcoln){
	case POOL_COLN_4: fmbuf_row_n >>= 2;break;
	case POOL_COLN_8: fmbuf_row_n >>= 3;break;
	case POOL_COLN_16: fmbuf_row_n >>= 4;break;
	case POOL_COLN_32: fmbuf_row_n >>= 5;break;
	case POOL_COLN_64: fmbuf_row_n >>= 6;break;
	case POOL_COLN_128: fmbuf_row_n >>= 7;break;
	case POOL_COLN_256: fmbuf_row_n >>= 8;break;
	case POOL_COLN_512: fmbuf_row_n >>= 9;break;
	case POOL_COLN_1024: fmbuf_row_n >>= 10;break;
	case POOL_COLN_2048: fmbuf_row_n >>= 11;break;
	case POOL_COLN_4096: fmbuf_row_n >>= 12;break;
	}

	if(fmbuf_row_n > (uint32_t)handler->property.max_fmbuf_row_n){
		fmbuf_row_n = (uint32_t)handler->property.max_fmbuf_row_n;
	}

	bank_n_foreach_mid_res_row =
		ofmap_w / handler->property.mid_res_buf_bank_depth +
		(ofmap_w % handler->property.mid_res_buf_bank_depth ? 1:0);
	mid_res_buf_row_n_bufferable =
		handler->property.mid_res_buf_bank_n / bank_n_foreach_mid_res_row;

	if(!handler->property.up_sample_supported){
		return -2;
	}

	if(
		(cal_cfg->cal_fmt == POOL_INT8 && (!handler->property.int8_supported)) ||
		(cal_cfg->cal_fmt == POOL_INT16 && (!handler->property.int16_supported)) ||
		(cal_cfg->cal_fmt == POOL_FP16 && (!handler->property.fp16_supported))
	){
		return -2;
	}

	if(cal_cfg->use_post_mac && (!handler->property.post_mac_supported)){
		return -2;
	}

	if(
		(fmap_cfg->external_padding_left || fmap_cfg->external_padding_right || fmap_cfg->external_padding_top || fmap_cfg->external_padding_bottom) &&
		(!handler->property.ext_padding_supported)
	){
		return -2;
	}

	if(cal_cfg->non_zero_const_padding_mode && (!handler->property.non_zero_const_padding_supported)){
		return -2;
	}

	handler->reg_region_cal_cfg->cal_cfg0 =
		(((uint32_t)PROC_MODE_UPSP) << 0) |
		(((uint32_t)cal_cfg->cal_fmt) << 4);
	handler->reg_region_cal_cfg->cal_cfg1 =
		(((uint32_t)(cal_cfg->upsample_horizontal_n - 1)) << 0) |
		(((uint32_t)(cal_cfg->upsample_vertical_n - 1)) << 8);
	handler->reg_region_cal_cfg->cal_cfg2 =
		(((uint32_t)cal_cfg->non_zero_const_padding_mode) << 0) |
		(((uint32_t)cal_cfg->const_to_fill) << 16);

	if(cal_cfg->use_post_mac){
		uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

		handler->reg_region_ctrl->ctrl0 = pre_ctrl0 | (0x00000001 << 9);

		handler->reg_region_cal_cfg->cal_cfg3 =
			(((uint32_t)cal_cfg->post_mac_is_a_eq_1) << 0) |
			(((uint32_t)cal_cfg->post_mac_is_b_eq_0) << 1) |
			(((uint32_t)cal_cfg->post_mac_fixed_point_quat_accrc) << 8);
		handler->reg_region_cal_cfg->cal_cfg4 =
			(uint32_t)cal_cfg->post_mac_param_a;
		handler->reg_region_cal_cfg->cal_cfg5 =
			(uint32_t)cal_cfg->post_mac_param_b;
	}else{
		uint32_t pre_ctrl0 = handler->reg_region_ctrl->ctrl0;

		handler->reg_region_ctrl->ctrl0 = pre_ctrl0 & (~(0x00000001 << 9));
	}

	handler->reg_region_fmap_cfg->fmap_cfg0 =
		(uint32_t)fmap_cfg->ifmap_baseaddr;
	handler->reg_region_fmap_cfg->fmap_cfg1 =
		(uint32_t)fmap_cfg->ofmap_baseaddr;
	handler->reg_region_fmap_cfg->fmap_cfg2 =
		(((uint32_t)(fmap_cfg->ifmap_w - 1)) << 0) |
		(((uint32_t)(fmap_cfg->ifmap_h - 1)) << 16);
	handler->reg_region_fmap_cfg->fmap_cfg3 =
		ifmap_size - 1;
	handler->reg_region_fmap_cfg->fmap_cfg4 =
		(((uint32_t)(fmap_cfg->ifmap_c - 1)) << 0) |
		(((uint32_t)fmap_cfg->external_padding_left) << 16) |
		(((uint32_t)fmap_cfg->external_padding_top) << 24);
	handler->reg_region_fmap_cfg->fmap_cfg5 =
		(((uint32_t)(ext_fmap_w - 1)) << 0) |
		(((uint32_t)(ext_fmap_h - 1)) << 16);
	handler->reg_region_fmap_cfg->fmap_cfg6 =
		(((uint32_t)(ofmap_w - 1)) << 0) |
		(((uint32_t)(ofmap_h - 1)) << 15) |
		(((uint32_t)fmap_cfg->ofmap_data_type) << 30);

	handler->reg_region_buffer_cfg->buf_cfg0 =
		(((uint32_t)(buffer_cfg->fmbufcoln)) << 0) |
		(((uint32_t)fmbuf_row_n) << 16);
	handler->reg_region_buffer_cfg->buf_cfg1 =
		(uint32_t)(mid_res_buf_row_n_bufferable - 1);

	return 0;
}

/*************************
@sts
@public
@brief  查询DMA命令完成数
@param  handler 通用池化处理单元(加速器句柄)
        query_type 查询类型
@return 命令完成数
*************************/
uint32_t axi_generic_pool_get_cmd_fns_n(AxiGnrPoolHandler* handler, AxiGnrPoolCmdFnsNQueryType query_type){
	switch(query_type){
	case Q_CMD_FNS_N_MM2S:
		return handler->reg_region_sts->sts1;
	case Q_CMD_FNS_N_S2MM:
		return handler->reg_region_sts->sts2;
	}

	return 0xFFFFFFFF;
}

/*************************
@ctrl
@public
@brief  清除DMA命令完成数计数器
@param  handler 通用池化处理单元(加速器句柄)
        clr_type 待清除的命令完成数计数器类型
@return 是否成功
*************************/
int axi_generic_pool_clr_cmd_fns_n(AxiGnrPoolHandler* handler, AxiGnrPoolCmdFnsNClrType clr_type){
	if(clr_type == C_CMD_FNS_N_MM2S || clr_type == C_ALL){
		handler->reg_region_sts->sts1 = 0;
	}

	if(clr_type == C_CMD_FNS_N_S2MM || clr_type == C_ALL){
		handler->reg_region_sts->sts2 = 0;
	}

	return 0;
}

/*************************
@sts
@public
@brief  获取性能监测计数器的值
@param  handler 通用池化处理单元(加速器句柄)
@return 性能监测计数器的值
*************************/
uint32_t axi_generic_pool_get_pm_cnt(AxiGnrPoolHandler* handler){
	return handler->reg_region_sts->sts3;
}

/*************************
@ctrl
@public
@brief  清除性能监测计数器
@param  handler 通用池化处理单元(加速器句柄)
@return 是否成功
*************************/
int axi_generic_pool_clr_pm_cnt(AxiGnrPoolHandler* handler){
	if(!handler->property.performance_monitor_supported){
		return -1;
	}

	handler->reg_region_sts->sts3 = 0;

	return 0;
}
