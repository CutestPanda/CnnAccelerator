/************************************************************************************************************************
基于FATFS的SD卡读写操作库
@brief  实现了基于FATFS的SD卡的文件读写操作
              实现了文件的格式化读写
@date   2022/09/24
@author 陈家耀
@eidt   none
************************************************************************************************************************/

#include "sd_card_fatfs.h"

#include <stdarg.h>
#include <ctype.h>
#include <string.h>

typedef char* charptr;

////////////////////////////////////////////////////////////////////////////////////////////////////////////

//文件的格式化输出(类型和函数定义)->

typedef struct params_s {
    s32 len;
    s32 num1;
    s32 num2;
    char8 pad_character;
    s32 do_padding;
    s32 left_flag;
    s32 unsigned_flag;
}params_t;

static s32 getnum( charptr* linep);
static int outnum( FIL* file, const s32 n, const s32 base, struct params_s *par);
static int padding( FIL* file, const s32 l_flag, const struct params_s *par);
static int outs( FIL* file, const charptr lp, struct params_s *par);
char sd_printf_temp;

static s32 getnum( charptr* linep)
{
    s32 n;
    s32 ResultIsDigit = 0;
    charptr cptr;
    n = 0;
    cptr = *linep;
	if(cptr != NULL){
		ResultIsDigit = isdigit(((s32)*cptr));
	}
    while (ResultIsDigit != 0) {
		if(cptr != NULL){
			n = ((n*10) + (((s32)*cptr) - (s32)'0'));
			cptr += 1;
			if(cptr != NULL){
				ResultIsDigit = isdigit(((s32)*cptr));
			}
		}
		ResultIsDigit = isdigit(((s32)*cptr));
	}
    *linep = ((charptr )(cptr));
    return(n);
}

static int outnum( FIL* file, const s32 n, const s32 base, struct params_s *par)
{
    s32 negative;
	s32 i;
    char8 outbuf[32];
    const char8 digits[] = "0123456789ABCDEF";
    u32 num;
    for(i = 0; i<32; i++) {
	outbuf[i] = '0';
    }

    /* Check if number is negative                   */
    if ((par->unsigned_flag == 0) && (base == 10) && (n < 0L)) {
        negative = 1;
		num =(-(n));
    }
    else{
        num = n;
        negative = 0;
    }

    /* Build number (backwards) in outbuf            */
    i = 0;
    do {
		outbuf[i] = digits[(num % base)];
		i++;
		num /= base;
    } while (num > 0);

    if (negative != 0) {
		outbuf[i] = '-';
		i++;
	}

    outbuf[i] = 0;
    i--;

    /* Move the converted number to the buffer and   */
    /* add in the padding where needed.              */
    par->len = (s32)strlen(outbuf);
    if(!padding(file, !(par->left_flag), par)){
    	return 0;
    }
    while (&outbuf[i] >= outbuf) {
#ifdef STDOUT_BASEADDRESS
	if(!sd_card_fatfs_fwrite(file, outbuf+i, 1)){
		return 0;
	}
#endif
		i--;
}
    if(!padding(file, par->left_flag, par)){
    	return 0;
    }

    return 1;
}

static int padding( FIL* file, const s32 l_flag, const struct params_s *par)
{
    s32 i;

    if ((par->do_padding != 0) && (l_flag != 0) && (par->len < par->num1)) {
		i=(par->len);
        for (; i<(par->num1); i++) {
#ifdef STDOUT_BASEADDRESS
        	sd_printf_temp = par->pad_character;
        	if(!sd_card_fatfs_fwrite(file, &sd_printf_temp, 1)){
        		return 0;
        	}
#endif
		}
    }

    return 1;
}

static int outs(FIL* file, const charptr lp, struct params_s *par)
{
    charptr LocalPtr;
	LocalPtr = lp;
    /* pad on left if needed                         */
	if(LocalPtr != NULL) {
		par->len = (s32)strlen( LocalPtr);
	}
	if(!padding(file, !(par->left_flag), par)){
		return 0;
	}
    /* Move string to the buffer                     */
    while (((*LocalPtr) != (char8)0) && ((par->num2) != 0)) {
		(par->num2)--;
#ifdef STDOUT_BASEADDRESS
        if(!sd_card_fatfs_fwrite(file, LocalPtr, 1)){
        	return 0;
        }
#endif
		LocalPtr += 1;
}

    /* Pad on right if needed                        */
    /* CR 439175 - elided next stmt. Seemed bogus.   */
    /* par->len = strlen( lp)                      */
    if(!padding(file, par->left_flag, par)){
    	return 0;
    }

    return 1;
}

////////////////////////////////////////////////////////////////////////////////////////////////////////////

/*************************
@init
@public
@brief  初始化文件系统
@param  fatfs 文件系统句柄(指针)
        sd_NO SD卡控制器编号 可选:0|1
@return 是否成功
*************************/
int init_sd_card_fatfs(FATFS* fatfs, BYTE sd_NO)
{
	TCHAR *Path = "0:/";
	BYTE work[FF_MAX_SS];

    //注册一个工作区(挂载分区文件系统)
    //在使用任何其它文件函数之前，必须使用f_mount函数为每个使用卷注册一个工作区
	FRESULT status = f_mount(fatfs, Path, sd_NO);  //挂载SD卡
	if (status != FR_OK) {
		//挂载失败
		status = f_mkfs(Path, FM_FAT32, 0, work, sizeof(work)); //格式化SD卡
		if (status != FR_OK) {
			return -1;
		}
		status = f_mount(fatfs, Path, sd_NO); //格式化后重新挂载SD卡
		if (status != FR_OK) {
			return -1;
		}
	}

	return 0;
}

/*************************
@IO
@public
@brief  按给定模式打开某个文件,文件读/写指针移动到给定位置
@param  file 文件对象(指针)
        file_name 文件名(指针)
        mode 打开模式 可选:FA_READ FA_WRITE FA_OPEN_EXISTING FA_CREATE_NEW FA_CREATE_ALWAYS
                          FA_OPEN_ALWAYS FA_OPEN_APPEND
        file_pos 文件指针的初始位置
@return 是否成功
*************************/
int sd_card_fatfs_fopen(FIL* file, char* file_name, BYTE mode, FSIZE_t file_pos)
{
	FRESULT status = f_open(file, file_name, mode); //打开一个文件(不存在时自动创建)
	if (status != FR_OK) {
		return -1;
	}
	status = f_lseek(file, file_pos); //移动打开的文件对象的文件读/写指针到给定位置
	if (status != FR_OK) {
		return -1;
	}

	return 0;
}

/*************************
@IO
@public
@brief  从SD卡读取给定长度的数据并存入缓冲区
@param  file 文件对象(指针)
        buff 读缓冲区(首地址)
        len  要读取的长度
@return 成功读取的长度
*************************/
int sd_card_fatfs_fread(FIL* file, void* buff, UINT len)
{
	UINT read_n;
	FRESULT status = f_read(file, buff, len, &read_n);

	if(status != FR_OK){
		return 0;
	}else{
		return read_n;
	}
}

/*************************
@IO
@public
@brief  移动文件指针到指定的位置
@param  file 文件对象(指针)
        ofs 偏移量
@return 是否成功
*************************/
int sd_card_fatfs_fseek(FIL* file, u32 ofs){
	if(f_lseek(file, ofs) != FR_OK){
		return -1;
	}else{
		return 0;
	}
}

/*************************
@IO
@public
@brief  从缓冲区向SD卡写入给定长度的数据
@param  file 文件对象(指针)
        buff 写缓冲区(首地址)
        len  要写入的长度
@return 成功写入的长度
*************************/
int sd_card_fatfs_fwrite(FIL* file, void* buff, UINT len)
{
	UINT write_n;
	FRESULT status = f_write(file, buff, len, &write_n);

	if(status != FR_OK){
		return 0;
	}else{
		return write_n;
	}
}

/*************************
@IO
@public
@brief  关闭文件
@param  file 文件对象(指针)
@return 是否成功
*************************/
int sd_card_fatfs_fclose(FIL* file)
{
	FRESULT status = f_close(file);

	if(status != FR_OK){
		return -1;
	}else{
		return 0;
	}
}

/*************************
@IO
@public
@brief  按格式读取文件
@param  file 文件对象(指针)
        fmt 读取格式(指针) 支持:%c%d%f%s
        ... 变量地址(不定参数组)
@return 成功读取到的变量个数(失败时返回EOF)
*************************/
int sd_card_fatfs_fscanf(FIL* file, char* fmt, ...)
{
	int res = 1;
    int count = 0, i = 0;
    char input;
	int input2 = -1;
    int d, sign, point_en, first, * pd;
    char* s;
    float f, f2, f3, * pf;
    va_list ap;
    va_start(ap, fmt);
    while (fmt[i])
    {
        if (fmt[i] == '%')
        {
            i++;
            switch (fmt[i])
            {
            case 'c':
                s = va_arg(ap, char*);
                if (input2 != -1) {
                    input = input2;
                    input2 = -1;
                }
                else {
                    if (input2 != -1) {
                        input = input2;
                        input2 = -1;
                    }
                    else {
                    	res = sd_card_fatfs_fread(file, &input, 1);
                    }
                }
                if (!res)
                    goto END_EOF;
                *s = input;
                count++;
                break;
            case 'f':
                pf = va_arg(ap, float*);
                f = 0;
                f2 = 0;
                f3 = 0.1;
                first = 1;
                sign = 1;
                point_en = 0;
                while (1)
                {
                    if (input2 != -1) {
                        input = input2;
                        input2 = -1;
                    }
                    else {
                    	res = sd_card_fatfs_fread(file, &input, 1);
                    }
                    if (!res)
                        goto END_EOF;
                    else if (input >= '0' && input <= '9')
                    {
                        if (point_en) {
                            f2 += f3 * (input - '0');
                            f3 /= 10;
                        }
                        else {
                            f *= 10;
                            f += input - '0';
                            if (first)
                                first = 0;
                        }
                    }
                    else if (input == '.') {
                        if (!point_en) {
                            point_en = 1;
                        }
                    }
                    else
                    {
                        if (first)
                        {
                            if (input == '+')
                            {
                                sign = 1;
                                first = 0;
                            }
                            else if (input == '-')
                            {
                                sign = -1;
                                first = 0;
                            }
                            else
                                goto END;
                        }
                        else
                        {
                            *pf = sign * (f + f2);
                            count++;
                            input2 = input;
                            break;
                        }
                    }
                }
                break;
            case 'd':
                pd = va_arg(ap, int*);
                d = 0;
                first = 1;
                sign = 1;
                while (1)
                {
                    if (input2 != -1) {
                        input = input2;
                        input2 = -1;
                    }
                    else {
                    	res = sd_card_fatfs_fread(file, &input, 1);
                    }
                    if (!res)
                        goto END_EOF;
                    else if (input >= '0' && input <= '9')
                    {
                        d *= 10;
                        d += input - '0';
                        if (first)
                            first = 0;
                    }
                    else
                    {
                        if (first)
                        {
                            if (input == '+')
                            {
                                sign = 1;
                                first = 0;
                            }
                            else if (input == '-')
                            {
                                sign = -1;
                                first = 0;
                            }
                            else
                                goto END;
                        }
                        else
                        {
                            *pd = sign * d;
                            count++;
                            input2 = input;
                            break;
                        }
                    }
                }
                break;
            case 's':
                s = va_arg(ap, char*);
                while (1)
                {
                    if (input2 != -1) {
                        input = input2;
                        input2 = -1;
                    }
                    else {
                    	res = sd_card_fatfs_fread(file, &input, 1);
                    }
                    if (!res)
                        goto END_EOF;
                    else if (!isspace(input))
                        *s++ = input;
                    else
                    {
                        *s = '\0';
                        count++;
                        input2 = input;
                        break;
                    }
                }
                break;
            default:
                goto END;
            }
        }
        else
        {
            if (input2 != -1) {
                input = input2;
                input2 = -1;
            }
            else {
            	res = sd_card_fatfs_fread(file, &input, 1);
            }
            if (!res)
                goto END_EOF;
            else if (input != fmt[i])
            {
                input2 = input;
                goto END;
            }
        }
        i++;
    }

	END:
		va_end(ap);
		return count;
	END_EOF:
		va_end(ap);
		return EOF;
}

/*************************
@IO
@public
@brief  按格式写入文件
@param  file 文件对象(指针)
        fmt 格式化输出(字符串)
        ... 输出的变量/常量(不定参数组)
@return 是否成功
*************************/
int sd_card_fatfs_fprintf(FIL* file, char* fmt, ...){
	s32 Check;
#if defined (__aarch64__) || defined (__arch64__)
    s32 long_flag;
#endif
    s32 dot_flag;

    params_t par;

    char8 ch;
    va_list argp;
    char8 *ctrl = (char8 *)fmt;

    va_start( argp, fmt);

    while ((ctrl != NULL) && (*ctrl != (char8)0)) {

        /* move format string chars to buffer until a  */
        /* format control is found.                    */
        if (*ctrl != '%') {
#ifdef STDOUT_BASEADDRESS
        	if(!sd_card_fatfs_fwrite(file, ctrl, 1)){
        		return -1;
        	}
#endif
			ctrl += 1;
            continue;
        }

        /* initialize all the flags for this format.   */
        dot_flag = 0;
#if defined (__aarch64__) || defined (__arch64__)
		long_flag = 0;
#endif
        par.unsigned_flag = 0;
		par.left_flag = 0;
		par.do_padding = 0;
        par.pad_character = ' ';
        par.num2=32767;
		par.num1=0;
		par.len=0;

 try_next:
		if(ctrl != NULL) {
			ctrl += 1;
		}
		if(ctrl != NULL) {
			ch = *ctrl;
		}
		else {
			ch = *ctrl;
		}

        if (isdigit((s32)ch) != 0) {
            if (dot_flag != 0) {
                par.num2 = getnum(&ctrl);
			}
            else {
                if (ch == '0') {
                    par.pad_character = '0';
				}
				if(ctrl != NULL) {
			par.num1 = getnum(&ctrl);
				}
                par.do_padding = 1;
            }
            if(ctrl != NULL) {
			ctrl -= 1;
			}
            goto try_next;
        }


		if(tolower((s32)ch) == 'f'){
			float f = *va_arg(argp, float*);
			int f_z;
			float f_d;
			int f_d2;
			char f_d3[6], f_d4[6];
			if(f < 0){
				if(!sd_card_fatfs_fwrite(file, "-", 1)){
					return -1;
				}
				f = -f;
			}
			f_z = (int)f;
			f_d = (f - f_z)*1000000;
			f_d2 = f_d - (int)f_d;
			f_d2 = (int)f_d + (f_d2 >= 0.5);
			if(!outnum(file, f_z, 10L, &par)){
				return -1;
			}
			if(!sd_card_fatfs_fwrite(file, ".", 1)){
				return -1;
			}
			for(int i = 0;i < 6;i++){
				if(f_d2){
					f_d3[i] = '0' + (f_d2 % 10);
					f_d2 /= 10;
				}else{
					f_d3[i] = '0';
				}
			}
			for(int i = 5;i >= 0;i--){
				f_d4[5 - i] = f_d3[i];
			}
			if(!sd_card_fatfs_fwrite(file, f_d4, 6)){
				return -1;
			}
			Check = 1;
		}else{
			switch (tolower((s32)ch)) {
				case '%':
	#ifdef STDOUT_BASEADDRESS
					if(!sd_card_fatfs_fwrite(file, "%", 1)){
						return -1;
					}
	#endif
					Check = 1;
					break;
				case '-':
					par.left_flag = 1;
					Check = 0;
					break;

				case '.':
					dot_flag = 1;
					Check = 0;
					break;

				case 'l':
				#if defined (__aarch64__) || defined (__arch64__)
					long_flag = 1;
				#endif
					Check = 0;
					break;

				case 'u':
					par.unsigned_flag = 1;
					/* fall through */
				case 'i':
				case 'd':
					#if defined (__aarch64__) || defined (__arch64__)
					if (long_flag != 0){
						outnum1((s64)va_arg(argp, s64), 10L, &par);
					}
					else {
						outnum( va_arg(argp, s32), 10L, &par);
					}
					#else
						if(!outnum(file, va_arg(argp, s32), 10L, &par)){
							return -1;
						}
					#endif
					Check = 1;
					break;
				case 'p':
					#if defined (__aarch64__) || defined (__arch64__)
					par.unsigned_flag = 1;
					outnum1((s64)va_arg(argp, s64), 16L, &par);
					Check = 1;
					break;
					#endif
				case 'X':
				case 'x':
					par.unsigned_flag = 1;
					#if defined (__aarch64__) || defined (__arch64__)
					if (long_flag != 0) {
						outnum1((s64)va_arg(argp, s64), 16L, &par);
					}
					else {
						outnum((s32)va_arg(argp, s32), 16L, &par);
					}
					#else
					if(!outnum(file, (s32)va_arg(argp, s32), 16L, &par)){
						return -1;
					}
					#endif
					Check = 1;
					break;

				case 's':
					if(!outs(file, va_arg( argp, char *), &par)){
						return -1;
					}
					Check = 1;
					break;

				case 'c':
	#ifdef STDOUT_BASEADDRESS
					sd_printf_temp = va_arg( argp, s32);
					if(!sd_card_fatfs_fwrite(file, &sd_printf_temp, 1)){
						return -1;
					}
	#endif
					Check = 1;
					break;

				case '\\':
					switch (*ctrl) {
						case 'a':
	#ifdef STDOUT_BASEADDRESS
							sd_printf_temp = 0x07;
							if(!sd_card_fatfs_fwrite(file, &sd_printf_temp, 1)){
								return -1;
							}
	#endif
							break;
						case 'h':
	#ifdef STDOUT_BASEADDRESS
							sd_printf_temp = 0x08;
							if(!sd_card_fatfs_fwrite(file, &sd_printf_temp, 1)){
								return -1;
							}
	#endif
							break;
						case 'r':
	#ifdef STDOUT_BASEADDRESS
							sd_printf_temp = 0x0D;
							if(!sd_card_fatfs_fwrite(file, &sd_printf_temp, 1)){
								return -1;
							}
	#endif
							break;
						case 'n':
	#ifdef STDOUT_BASEADDRESS
							sd_printf_temp = 0x0D;
							if(!sd_card_fatfs_fwrite(file, &sd_printf_temp, 1)){
								return -1;
							}
							sd_printf_temp = 0x0A;
							if(!sd_card_fatfs_fwrite(file, &sd_printf_temp, 1)){
								return -1;
							}
	#endif
							break;
						default:
	#ifdef STDOUT_BASEADDRESS
							if(!sd_card_fatfs_fwrite(file, ctrl, 1)){
								return -1;
							}
	#endif
							break;
					}
					ctrl += 1;
					Check = 0;
					break;

				default:
			Check = 1;
			break;
			}
		}

		if(Check == 1) {
			if(ctrl != NULL) {
				ctrl += 1;
			}
				continue;
		}
		goto try_next;

    }


    va_end( argp);

    return 0;
}
