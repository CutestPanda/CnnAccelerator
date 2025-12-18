import argparse
import os
import re

def parse_opt():
    parser = argparse.ArgumentParser()
    parser.add_argument("--res", type=str, default="mid_res_acmlt_cal_obsv_log.txt", help="res log")
    parser.add_argument("--exp", type=str, default="exp_fmap_cal_obsv_log.txt", help="exp log")
    parser.add_argument("--o", type=str, default="merged.txt", help="merged log")
    
    opt = parser.parse_args()
    
    return opt

def get_item_dict(path, str_to_clip = "cal_rid"):
    d = {}
    
    with open(path, 'r') as f:
        for line in f:
            line = line.strip()
            match = re.search(r'\[.+\]', line)
            
            if match:
                org_key = match.group(0)
                item_key = re.sub(", " + str_to_clip + " = \\d+", '', org_key)
            
            item_value = line.replace(org_key + ' ', '')
            
            d[item_key] = item_value
    
    return d

if __name__ == "__main__":
    opt = parse_opt()
    
    res_log = opt.res
    exp_log = opt.exp
    out_log = opt.o
    
    res_dict = get_item_dict(res_log, "cal_rid")
    exp_dict = get_item_dict(exp_log, "sfc_id")
    
    with open(out_log, 'w') as f:
        total_err = 0.0
        
        for key, value in res_dict.items():
            if key in exp_dict:
                match = re.search(r'\+ .+ =', value)
                res_num = re.sub("[\\+=\\s]", '', match.group(0))
                exp_num = exp_dict[key]
                
                err_num = float(exp_num) - float(res_num)
                
                total_err = total_err + err_num
                
                f.write(key + " " + value + "\n")
                f.write("结果 = " + res_num + " 期望 = " + exp_num + " 当前误差 = " + "{:.6f}".format(err_num) + " 累计误差 = " + "{:.6f}".format(total_err) + "\n")
                f.write("\n")
            else:
                f.write(key + " " + value + " ---\n")
                f.write("\n")
        
        f.write("最终误差 = " + "{:.6f}".format(total_err) + "\n")
