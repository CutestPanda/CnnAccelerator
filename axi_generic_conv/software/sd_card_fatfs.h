/************************************************************************************************************************
基于FATFS的SD卡读写操作库(接口头文件)
@brief  实现了基于FATFS的SD卡的文件读写操作
@date   2022/09/24
@author 陈家耀
************************************************************************************************************************/

#include "ff.h"

////////////////////////////////////////////////////////////////////////////////////////////////////////////

int init_sd_card_fatfs(FATFS* fatfs, BYTE sd_NO); //初始化文件系统
int sd_card_fatfs_fopen(FIL* file, char* file_name, BYTE mode, FSIZE_t file_pos); //打开文件
int sd_card_fatfs_fseek(FIL* file, u32 ofs); // 移动文件指针到指定的位置
int sd_card_fatfs_fread(FIL* file, void* buff, UINT len); //读取文件
int sd_card_fatfs_fwrite(FIL* file, void* buff, UINT len); //写入文件
int sd_card_fatfs_fclose(FIL* file); //关闭文件
int sd_card_fatfs_fscanf(FIL* file, char* fmt, ...); //格式化读取
int sd_card_fatfs_fprintf(FIL* file, char* fmt, ...); //格式化写入
