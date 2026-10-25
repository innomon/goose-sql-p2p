// Lightweight JSON parsing and formatting utility
namespace json_util;

import std;

fn escape_string(out: u8[>..]&, s: const u8[:]) {
    for c in s {
        if c == '"' {
            out.append("\\\"");
        } else if c == '\\' {
            out.append("\\\\");
        } else if c == '\n' {
            out.append("\\n");
        } else if c == '\r' {
            out.append("\\r");
        } else if c == '\t' {
            out.append("\\t");
        } else {
            out.push(c);
        }
    }
}

// Find field location in json: searches for "key" followed by optional spaces and ':'
fn find_field_pos(json_str: const u8[:], field: const u8[:]) -> i64 {
    var search: u8[>..] = [];
    search.push('"');
    search.append(field);
    search.push('"');

    var p = find(json_str, search);
    if p < 0 {
        return -1;
    }
    p = p + search.len;
    while p < json_str.len && (json_str[p] == ' ' || json_str[p] == '\t' || json_str[p] == '\n' || json_str[p] == '\r') {
        p++;
    }
    if p < json_str.len && json_str[p] == ':' {
        p++;
        while p < json_str.len && (json_str[p] == ' ' || json_str[p] == '\t' || json_str[p] == '\n' || json_str[p] == '\r') {
            p++;
        }
        return p;
    }
    return -1;
}

fn find_string_field(json_str: const u8[:], field: const u8[:], out: u8[>..]&) -> bool {
    var p = find_field_pos(json_str, field);
    if p < 0 || p >= json_str.len {
        return false;
    }

    if json_str[p] == '"' {
        p++;
        var escaped = false;
        while p < json_str.len {
            var c = json_str[p];
            if escaped {
                if c == 'n' { out.push('\n'); }
                else if c == 'r' { out.push('\r'); }
                else if c == 't' { out.push('\t'); }
                else if c == '"' { out.push('"'); }
                else if c == '\\' { out.push('\\'); }
                else { out.push(c); }
                escaped = false;
            } else if c == '\\' {
                escaped = true;
            } else if c == '"' {
                return true;
            } else {
                out.push(c);
            }
            p++;
        }
        return true;
    } else if json_str[p] == '{' {
        // Raw JSON object (e.g. metadata or data)
        var depth = 1;
        out.push('{');
        p++;
        var in_str = false;
        var esc = false;
        while p < json_str.len && depth > 0 {
            var c = json_str[p];
            out.push(c);
            if esc {
                esc = false;
            } else if c == '\\' && in_str {
                esc = true;
            } else if c == '"' {
                in_str = !in_str;
            } else if !in_str {
                if c == '{' { depth++; }
                else if c == '}' { depth--; }
            }
            p++;
        }
        return depth == 0;
    } else {
        // Value might be null, number, or boolean
        while p < json_str.len && json_str[p] != ',' && json_str[p] != '}' && json_str[p] != ']' && json_str[p] != '\n' && json_str[p] != '\r' {
            if json_str[p] != ' ' && json_str[p] != '\t' {
                out.push(json_str[p]);
            }
            p++;
        }
        return out.len > 0;
    }
}

fn parse_int(str_val: const u8[:], default_val: i64) -> i64 {
    if str_val.len == 0 {
        return default_val;
    }
    var val: i64 = 0;
    var neg = false;
    var i = 0;
    if str_val[0] == '-' {
        neg = true;
        i = 1;
    }
    var digits_found = false;
    while i < str_val.len {
        var c = str_val[i];
        if c >= '0' && c <= '9' {
            val = val * 10 + (c - '0');
            digits_found = true;
        } else {
            break;
        }
        i++;
    }
    if !digits_found {
        return default_val;
    }
    if neg {
        return -val;
    }
    return val;
}

fn find_int_field(json_str: const u8[:], field: const u8[:], default_val: i64) -> i64 {
    var raw: u8[>..] = [];
    if !find_string_field(json_str, field, raw) || raw.len == 0 {
        return default_val;
    }
    return parse_int(raw, default_val);
}

fn find_bool_field(json_str: const u8[:], field: const u8[:], default_val: bool) -> bool {
    var raw: u8[>..] = [];
    if !find_string_field(json_str, field, raw) || raw.len == 0 {
        return default_val;
    }
    if raw == "true" || raw == "1" {
        return true;
    }
    if raw == "false" || raw == "0" {
        return false;
    }
    return default_val;
}

fn find_string_array(json_str: const u8[:], field: const u8[:], out_arr: u8[..128][>..]&) {
    var p = find_field_pos(json_str, field);
    if p < 0 || p >= json_str.len {
        return;
    }
    if json_str[p] != '[' {
        return;
    }
    p++;
    while p < json_str.len && json_str[p] != ']' {
        while p < json_str.len && (json_str[p] == ' ' || json_str[p] == '\t' || json_str[p] == '\n' || json_str[p] == '\r' || json_str[p] == ',') {
            p++;
        }
        if p < json_str.len && json_str[p] == '"' {
            p++;
            var item: u8[>..] = [];
            var esc = false;
            while p < json_str.len {
                var c = json_str[p];
                if esc {
                    if c == 'n' { item.push('\n'); }
                    else if c == 'r' { item.push('\r'); }
                    else if c == 't' { item.push('\t'); }
                    else if c == '"' { item.push('"'); }
                    else if c == '\\' { item.push('\\'); }
                    else { item.push(c); }
                    esc = false;
                } else if c == '\\' {
                    esc = true;
                } else if c == '"' {
                    p++;
                    break;
                } else {
                    item.push(c);
                }
                p++;
            }
            if item.len > 0 {
                var bounded: u8[..128] = [];
                bounded.append(item);
                out_arr.push(bounded);
            }
        } else if p < json_str.len && json_str[p] == ']' {
            break;
        } else {
            p++;
        }
    }
}
