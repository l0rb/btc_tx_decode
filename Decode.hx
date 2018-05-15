/*
    one hex digit is a nibble, which is half a byte
    so we always need two hex digits to make one byte

    there isn't a byte type in haxe, so I'm using ints instead.
    (the full story is of course more complicate. there is haxe.io.Bytes
     and haxe.io.BytesData for example, but they have there own issues)

    most stuff in a raw tx is little endian. that's why there are
    so many array.reverse() calls. reversing the whole raw_tx and
    working from the end would also work but feels unnatural
*/

import haxe.Int64; // UInt64 does not exist in most targets : (
import StringTools;
import haxe.crypto.Sha256;
import haxe.io.Bytes;

#if php
    import php.Lib;
    import php.Web;
#end

#if sys
    import sys.io.File;
    import haxe.Template;
#end

class Decode {
    static public function main():Void {
        var hex = get_tx();
        var tx = null;
        if(hex != null) {
            tx = new FancyTx(hex);
        }
        var file_content = sys.io.File.getContent("../decode.tpl");
        var tpl = new haxe.Template(file_content);
        var output = tpl.execute({tx:tx});
        php.Lib.print(output);
    }

    static public function get_tx():String {
#if php
            var hex = Web.getParams()["hex"];
#else
            // do some fancy input thing here?
            //var hash:String = "de77a762de896660005c3b43dc47c60ec30799985e910f0e6b69b78ae3c5790e";
            var hex:String = "02000000024f0ae564c1f8a2425fb30b3b284a9af60c9a645ac3d4f6016481ec2a714ff0ff000000006a473044022100879bd08d49b63449b5f32b0e24e2e3dfd80f1369bbcfb83fba28538c7058e5b6021f0451f75d0f9d70a226a5159cdc557332e4f3a1381fcf28b01bd118ba34e96e012102854ce1ec65ea832859348b7d9fae1e7bf6bdf1168afc3d0e085c0e7fd06e62aafdffffff816d65ac23c4a393b57bb17c40b951e179325c33784296a107fa7a89f37c7a94000000006a473044022078274766268b7b3f98abfde8af84b12c2765ada9ff146fdcdc40d1e0eb82459d02207010e7cb5c734acd65616ad78ba032372606ce1588a01777065dcb3e6afa14c5012103d7d8cf8d1156fbfbc1e1cc04454827b4be67b999dfd8906250141d34a7616772fdffffff03b23b0f00000000001976a914a107ee7642791b75bfcf74c7cb255ea1e79e3d9b88acfcd31600000000001976a914d6507c014c0bcaf3380ce6d86562ea25e350344f88ac0e8d12000000000017a914ff94d93b444b0e8912e0e65e614a101a8b6ee1bd87ecf60700";
#end
        return hex;
    }
}

class Encoding {
    static public function hexstring_to_bytearray(hexstring:String):Array<Int> {
        var bytearray:Array<Int> = new Array<Int>();
        if(hexstring.length % 2 == 1) {
            // what am I supposed to do with half a byte? this is clearly an error, maybe a leading 0 is missing?
            trace("Not good");
            return bytearray;
        }
        var hexdigits = hexstring.split("");
        var byte = "";
        for(hexdigit in hexdigits) {
            byte += hexdigit;
            if(byte.length==2) {
                var as_int = Std.parseInt("0x" + byte);
                bytearray.push(Std.parseInt("0x" + byte));
                byte = "";
            }
        }
        return bytearray;
    }
    static public function bytearray_to_hexstring(bytearray:Array<Int>, reverse_endianness=false) {
        if(reverse_endianness) {
            bytearray = bytearray.copy();
            bytearray.reverse();
        }
        var hex:String = "";
        for(byte in bytearray)
            hex += StringTools.hex(byte, 2);
        return hex;
    }
    static public function splice_varint(bytearray:Array<Int>):Int64 {
        var first_byte = bytearray.shift();
        if(first_byte < 0xFD)
            return first_byte;
        var get_bytes = [8, 4, 2][0xFF - first_byte];
        var varint_bytes = bytearray.splice(0, get_bytes);
        varint_bytes.reverse();
        return bytes_to_int64(varint_bytes);
    }
    static public function splice_int32(bytearray:Array<Int>):Int {
        var bytes = bytearray.splice(0, 4);
        bytes.reverse();
        return bytes_to_int64(bytes).low; // todo: find a nice way to get int32 returned from bytes_to_int64
    }
    static public function splice_int64(bytearray:Array<Int>):Int64 {
        var bytes = bytearray.splice(0, 8);
        bytes.reverse();
        return bytes_to_int64(bytes);
    }
    static public function bytes_to_int64(bytearray:Array<Int>):Int64 {
        if(bytearray.length > 8) // buddy there is a problem, my ints only got 64 bits
            return -1;
        var result:Int64 = 0;
        for(byte in bytearray) {
            result <<= 8;
            result ^= byte;
        }
        return result;
    }
    static public function double256(bytes:Array<Int>):String {
        var as_string:String = "";
        for(byte in bytes)
            as_string += String.fromCharCode(byte);
        var bytes_again = Bytes.ofString(as_string);
        
        var tmp = Sha256.make(Sha256.make(bytes_again)).toString().split("");
        tmp.reverse(); // fucking in-place shit destroys my beautiful chaining
        return Bytes.ofString(tmp.join("")).toHex();
    }
}

class Tx {
    public var hex:String;
    public var bytes:Array<Int>;
    public var inputs:Array<TxIn>;
    public var outputs:Array<TxOut>;
    public var version:Int;
    public var locktime:Int;
    public var segwit:Int = 0;
    public var witness_size:Int = 0;
    public var hash:String = "hash";
    public var hash_bytes:Array<Int>;
    public var hash_bytes_string:String;

    public function new(hexstring) {
        hex = hexstring;
        bytes = Encoding.hexstring_to_bytearray(hex);
        var raw_tx = bytes.copy();
        hash_bytes = bytes.copy();

        version = Encoding.splice_int32(raw_tx);
        
        inputs = new Array<TxIn>(); 
        var n_txIn = Encoding.splice_varint(raw_tx);
        if(n_txIn == 0) {
            segwit = raw_tx.shift();
            n_txIn = Encoding.splice_varint(raw_tx);
        }
        for(n in 0...n_txIn.low) {
            inputs.push(TxIn.splice_from_bytearray(raw_tx));
        }
       
        outputs = new Array<TxOut>();
        var n_txOut = Encoding.splice_varint(raw_tx);
        for(n in 0...n_txOut.low) {
            outputs.push(TxOut.splice_from_bytearray(raw_tx));
        }
      
        if(segwit > 0) {
            var raw_before = raw_tx.length;
            for(input in inputs) {
                var segwit_items = Encoding.splice_varint(raw_tx);
                for(i in 0...segwit_items.low) {
                    var item_size = Encoding.splice_varint(raw_tx);
                    raw_tx.splice(0, item_size.low);
                }
            }
            witness_size = raw_before - raw_tx.length;
            hash_bytes.splice(4, 2); // first 8 bytes are version, next 2 bytes are segwit stuff
            hash_bytes.reverse();
            hash_bytes.splice(4, witness_size); // last 4 bytes are locktime, next n bytes are segwit stuff
            hash_bytes.reverse();
        }
        locktime = Encoding.splice_int32(raw_tx);
        hash = Encoding.double256(hash_bytes);
        hash_bytes_string = Encoding.bytearray_to_hexstring(hash_bytes);

        if(raw_tx.length > 0)
            trace("Warning: Extra bytes at end of tx. " + raw_tx);
    }
}

typedef FancyTxSection = {
    var hex:String;
    var color:String;
    var label:String;
    var human_readable:String;
}
class FancyTx extends Tx {
    public var sections:Array<FancyTxSection>;

    public function new(hexstring) {
        super(hexstring);
        _colored_hex();
    }
    private function _colored_hex():Void {
        sections = new Array<FancyTxSection>();
        var tmp_hex = hex;
        
        sections.push({hex:tmp_hex.substr(0, 8), color:"#22FF22", label:"Version", human_readable:Std.string(version)});
        tmp_hex = tmp_hex.substring(8);
       
        if(segwit > 0) {
            sections.push({hex:tmp_hex.substr(0, 2), color:"#009090", label:"Segwit Marker", human_readable:"Always 0"});
            tmp_hex = tmp_hex.substring(2);
            
            sections.push({hex:tmp_hex.substr(0, 2), color:"#00FFFF", label:"Segwit Flag", human_readable:Std.string(segwit)});
            tmp_hex = tmp_hex.substring(2);
        } 
        sections.push({hex:tmp_hex.substr(0, 2), color:"#FFFFFF", label:"Number of inputs", human_readable:Std.string(inputs.length)});
        tmp_hex = tmp_hex.substring(2);

        for(i in 1...(inputs.length+1)) {
            var input = inputs[i-1];
            var length = input.size * 2;
            var color = make_color(i, inputs.length, [255, 20, 20]);
            sections.push({hex:tmp_hex.substr(0, length), color:"#"+color, label:"Input #"+i, human_readable:input.prev_tx_hash + ":" + input.prev_tx_n});
            tmp_hex = tmp_hex.substring(length);
        }
        
        sections.push({hex:tmp_hex.substr(0, 2), color:"#FFFFFF", label:"Number of outputs", human_readable:Std.string(outputs.length)});
        tmp_hex = tmp_hex.substring(2);
        
        for(i in 1...(outputs.length+1)) {
            var length = 18 + outputs[i-1].script.hex.length;
            var color = make_color(i, outputs.length, [100, 100, 255]);
            sections.push({hex:tmp_hex.substr(0, length), color:"#"+color, label:"Output #"+i, human_readable:"Value: " + Std.string(outputs[i-1].value) + " Script: " + outputs[i-1].script.asm});
            tmp_hex = tmp_hex.substring(length);
        }
        if(witness_size > 0) { 
            sections.push({hex:tmp_hex.substr(0, witness_size*2), color:"#00C0C0", label:"Witness Program", human_readable:"-"});
            tmp_hex = tmp_hex.substring(witness_size*2);
        }
        
        sections.push({hex:tmp_hex, color:"#FFFF00", label:"Locktime", human_readable:Std.string(locktime)});
    }
    
    public function make_color(n:Int, of:Int, base:Array<Int>, min=50):String {
        var rgb = "";
        for(b in base)
            rgb += StringTools.hex(Std.int( min + ((b-min)/of) * n ), 2);
        return rgb;
    }
}

class Script {
    public var hex:String;
    public var bytearray:Array<Int>;
    public var asm:Array<Dynamic>;
    public static var OP_CODES = new Map<Int, String>();

    public function new(as_bytes:Array<Int>) {
        OP_CODES[118] = "OP_DUP";
        OP_CODES[135] = "OP_EQUAL";
        OP_CODES[136] = "OP_EQUALVERIFY";
        OP_CODES[169] = "OP_HASH160";
        OP_CODES[172] = "OP_CHECKSIG";
        this.hex = Encoding.bytearray_to_hexstring(as_bytes);
        this.bytearray = as_bytes.copy();
        var data_counter = 0;
        var data = "";
        this.asm = new Array<Dynamic>();
        for(key in 0...as_bytes.length) {
            var op = as_bytes[key];
            if(data_counter > 0) {
                data += StringTools.hex(op, 2);
                data_counter--;
                if(data_counter == 0) {
                    this.asm.push(data);
                    data = "";
                }
            } else if(op >= 1 && op <= 75) {
                data_counter = op;
                this.asm.push(op);
            } else if(OP_CODES[op] != null) {
                this.asm.push(OP_CODES[op]);
            } else {
                this.asm.push(op);
            }
        }
    }
}

class TxIn {
    public var prev_tx_hash:String;
    public var prev_tx_n:Int;
    public var script:Script;
    public var size:Int;

    static public function splice_from_bytearray(raw:Array<Int>):TxIn {
        var PrevTxOut_hash = Encoding.bytearray_to_hexstring(raw.splice(0, 32), true); // 32 bytes
        var PrevTxOut_n = Encoding.splice_int32(raw); // 4 bytes
        var raw_before = raw.length;
        var script_len = Encoding.splice_varint(raw); // usually 1 byte, but can be more
        var var_int_bytes = raw_before - raw.length;
        var size = 40 + var_int_bytes + script_len.low;
        var script = raw.splice(0, script_len.low); // script_len bytes
        var TxIn_n = Encoding.splice_int32(raw); // 4 bytes
        return new TxIn(PrevTxOut_hash, PrevTxOut_n, script, TxIn_n, size);
    }
    
    public function new(TxOutHash:String,TxOutIndex:Int,script:Array<Int>,Sequence:Int, size) {
        prev_tx_hash = TxOutHash;
        prev_tx_n = TxOutIndex;
        this.script = new Script(script);
        this.size = size;
    }
}

class TxOut {
    public var value:Int64;
    public var script:Script;

    static public function splice_from_bytearray(raw:Array<Int>):TxOut {
        var value = Encoding.splice_int64(raw); // 8 bytes
        var script_len = Encoding.splice_varint(raw); // usually 1 byte
        var script = raw.splice(0, script_len.low); // ? bytes
        return new TxOut(script, value);
    }
    
    public function new(script:Array<Int>, value:Int64) {
        this.value = value;
        this.script = new Script(script);
    }
}
