/*
db().query(sql, par);	// 查询多行数据，或仅执行语句
db().fetch(sql, par);	// 查询单行数据
db().scalar(sql,par);	// 查询第一行第一列值
db().lastSql;		// 得到最后一次执行的SQL语句
db().insert(table, row || rows);	// 向表中插入一行或多行数据
db().create(table, cols);	// 快速建表, db().create(表名, [ [名称类型，默认值，是否自动编号] ]);
db().close();		// 关闭数据库连接
db().table("test a")	// 开始链式表查询
	.where("id>?")
	.page("id desc", 15, 3, [0])	// 根据ID倒序，每页15条，查询第3页，查询参数。执行后db()对象下会生成 rownum, pagenum, curpage, pagesize 属性
	.astable('a')	// 将前面的查询结果作为临时表
	.join("users b on b.userid=a.userid", "left")	// 关联查询另一个表
	.select("a.id, count(b.userid) as usernum")	// 也可使用 field 方法别名
	.groupby("a.id")
	.having("usernum>0")
	.orderby("a.id desc")
	.query(par);	// 可以执行 query, fetch, scalar 中的一个，如果分页时传入了参数，则query时可免参数
*/
// WSH.Echo(db().query("select cast(@a as datetime) as today, cast(@b as int) as age", { a: new Date().getVarDate(), b: 43 }));
function db(dbPath, dbType) {
	if(!this.sys) this.sys = new Object;
	if(!dbPath) dbPath = sys.dbPath || "Data.sdf";
	if(!dbType) dbType = sys.dbType || "SqlLite";
	var isServer = dbType.toLowerCase() == "sqlserver";
	if("Server" in this) dbPath = isServer ? dbPath : Server.MapPath(dbPath);
	if(!sys.dbIns) sys.dbIns = new Object;
	var dbIns = sys.dbIns;
	if(dbIns[dbPath]) return dbIns[dbPath];
	dbIns[dbPath] = new SqlHelper(dbPath, isServer);
	return dbIns[dbPath];
}

function closeAllDb() {
	if(!sys.dbIns) return;
	for(var x in sys.dbIns) sys.dbIns[x].close();
}

function SqlHelper(dbPath, isServer) {
	// SQL CE 语法参考：https://docs.microsoft.com/zh-cn/previous-versions/sql/compact/sql-server-compact-4.0/ms173372(v=sql.110)
	var strConn = "Provider=" + (isServer ? "SqlOleDb" : "Microsoft.Windows.SqlLite.OleDb.4.0") + "; Data Source=" + dbPath;
	var dicType = { "string" : 202, "number" : 5, "boolean" : 11, "date" : 135, "unknown" : 205 };
	this.close  = function() {
		if(!("cmd" in this)) return;
		this.cmd.activeConnection.close();
		delete this.cmd;
	};
	this.table = function(tbl) {
		tbl = [ tbl ];
		var _select = "*", _with = "", where = "", groupby = "", having = "", orderby = "";
		var ins = new Object;
		ins.join = function(str, dir){
			if(!dir) dir = "left";
			tbl.push(dir + " join " + str);
			return ins;
		};
		ins.where = function(str){ where = " where " + str; return ins; };
		ins.groupby = function(str){ groupby = " group by " + str; return ins; };
		ins.having = function(str){ having = " having " + str; return ins; };
		ins.orderby = function(str){ orderby = " order by " + str; return ins; };
		ins.view = ins["with"] = function(str) { _with = "with " + str + "\r\n"; return ins; };
		ins.astable = function(str) {
			tbl = [ "(" + ins + ") " + str ];
			where = groupby = having = orderby = _with = "";
			_select = "*"; return ins;
		};
		ins.select = ins.field = function(str){ _select = str; return ins; };
		ins.query = function(par) { return me.query(ins.toString(), par || ins.pagePar || par); };
		ins.fetch = function(par) { return me.fetch(ins.toString(), par); };
		ins.scalar = function(par){ return me.scalar(ins.toString(), par); };
		ins.page = function(sort, size, page, par) {
			var bakCol = _select;
			me.pager = new Object; size = ~~size || 15;
			me.pager.rownum = ins.select("count(0)").scalar(par);
			me.pager.pagenum = Math.ceil(me.pager.rownum / size);
			me.pager.curpage = Math.min(page || 1, me.pager.pagenum);
			me.pager.pagesize = size;
			var start = Math.max((me.pager.curpage - 1) * size, 0);
			ins.select(bakCol).orderby(sort + " offset " + start + " rows fetch next " + size + " rows only");
			ins.pagePar = "unknown" == typeof par ? par.toArray() : par;
			return ins;
		};
		ins.toString = function() { return _with + "select " + _select + " from " + tbl.join(" ") + where + groupby + having + orderby; }
		return ins;
	};
	this.query = function(sql, arg, rowNum) {
		if("unknown" == typeof arg) arg = arg.toArray(); // VBArray?
		this.lastSql = { sql: sql, par: arg || [] };
		var cmd = getCmd();
		if(!isServer) {
			// SQL CE 模式
			cmd.commandText = sql;
			initParam(arg);
		} else {
			// SQL Server 模式
			initParam(arg);
			cmd.commandText = makeDeclare(arg) + sql;
		} try { var rs = cmd.execute(); }
		catch(err) { throw new Error(-1234567890, tojson({ err: err.message, cmd: this.lastSql })); }
		if(!rs.state) return new Array;
		var rows= new Array, cnt = rs.fields.count;
		var data = rs.EOF ? rows : rs.getRows(rowNum || -1).toArray();
		for(var i = 0; i < data.length; i += cnt) {
			var obj = new Object; rows.push(obj);
			for(var x = 0; x < cnt; x++) obj[rs.fields(x).name] = data[i + x];
		}
		rs.close(); return rows;
	};
	this.fetch = function(sql, arg) {
		var rows = this.query(sql, arg, 1);
		return rows[0];
	};
	this.scalar = function(sql, arg) {
		var row = this.fetch(sql, arg) || new Object;
		for(var x in row) return row[x];
	};
	this.insert = function(table, rows) {
		if(!(rows instanceof Array)) rows = [ rows ];
		var conn = getCmd().activeConnection;
		conn.beginTrans(); try {
		rows.forEach(function(row, i) {
			var cols = new Array, vals = new Array, pars = new Array;
			for(var x in row) {
				cols.push("[" + x + "]");
				vals.push("?");
				pars.push(row[x]);
			}
			me.query("insert into [" + table + "](" + cols.join(", ") + ") values(" + vals.join(", ") + ")", pars);
		});
		conn.commitTrans();
		} catch(err) { conn.rollbackTrans(); throw err; }
	};
	this.update = function(tbl, data, where) {
		var pars = new Array, arr = new Array, cond = new Array;
		for(var x in data) { arr.push("[" + x + "]=?"); pars.push(data[x]); }
		for(var x in where) { cond.push("[" + x + "]=?"); pars.push(where[x]); }
		me.query("update [" + tbl + "] set " + arr.join(", ") + " where " + cond.join(" and "), pars);
	};
	this.create = function(table, cols) {
		// db().create("test", [ ["id int", null, true ], "nick nvarchar(40)", [ "addtime datetime", "getdate()" ] ]);
		cols.forEach(function(col, i) {
			if(!(col instanceof Array)) col = [col];
			cols[i] = col[0];
			if(col[1] === i.x) col[1] = null;
			if(col[1] !== null) cols[i] += " not null default " + col[1];
			if(col[2]) cols[i] += " identity primary key";
		});
		me.query("create table [" + table + "](" + cols.join(", ") + ")");
	};
	function getCmd() {
		if("cmd" in me) return me.cmd;
		var conn = new ActiveXObject("Adodb.Connection"); try {
		conn.open(strConn); } catch(err) {
		if(isServer) throw err;	// SQL Server 模式直接抛出异常
		var cat = new ActiveXObject("AdoX.Catalog");
		cat.create(strConn);
		conn = cat.activeConnection; }
		me.cmd = new ActiveXObject("Adodb.Command");
		me.cmd.activeConnection = conn;
		return me.cmd;
	}
	function initParam(arg) {
		var pars = me.cmd.parameters;
		while(pars.count) pars.Delete(0);
		if(!arg) return;
		for(var x in arg) {
			if("function" == typeof arg[x]) continue;
			var type = dicType[typeof arg[x]] || 203;
			if(type == 202 && arg[x].length > 4000) type = 203;		// SQL CE NVarchar 最大值为 4000
			// 传数组时，实际参数名为 @P1, @P2
			var col = "number" == typeof x ? "P" + (x + 1) : x;
			var par = me.cmd.createParameter("@" + col, type, 1, type == 202 ? arg[x].length || 1 : -1, arg[x]);
			pars.append(par);
		}
		// SqlOleDb 区分 true 和 false
		me.cmd.namedParameters = !(arg instanceof Array);
	}
	// 生成 SQL Server 参数定义
	function makeDeclare(arg) {
		if(!arg) return "";
		if(arg instanceof Array) return "";
		var arr1 = new Array, arr2 = new Array;
		var getType = function(val) {
			switch(typeof val) {
				case "number": return "float";
				case "date": return "datetime";
				case "boolean": return "int";
				case "unknown": return "image"
				case "object": return "nchar";
				case "undefined": return "nchar";
			}
			return "nvarchar(" + val.length + ")";
		}
		for(var x in arg) {
			if("function" == typeof arg[x]) continue;
			arr1.push("@" + x + " " + getType(arg[x]));
			arr2.push("set @" + x + "=?");
		}
		if(!arr1.length) return "";
		// SQL Server 自定义参数名补丁，必须先 declare
		return "declare " + arr1.join(", ") + ";\r\n" + arr2.join(";") + ";\r\n";
	}
	var me = this, pro = Array.prototype;
	pro.toString = function() { return tojson(this); };
	pro.forEach = function(f) { for(var i = 0; i < this.length; i++) f(this[i], i); };
	Object.prototype.toString = function() { return tojson(this); };
}

function tojson(obj) {
	switch(typeof obj) {
		case "string": return toStr();
		case "number": return toNum();
		case "object": return toObj(obj);
		case "boolean": return toBool();
		case "date": return toTime();
		case "function": return obj;
		case "undefined": return "null";	//'"undefined"';
		default: return '"unknown"';
	}
	function toStr() { return '"' + obj.replace(/[\"\\]/g, function(str) { return "\\" + str; }).replace(/\r/g, "\\r").replace(/\n/g, "\\n").replace(/\t/g, "\\t") + '"'; }
	function toNum() { return obj; }
	function toBool() { return obj ? "true" : "false"; }
	function toObj() {
		if(!obj) return "null";
		// if(obj instanceof Array) return toArr();
		if("unshift" in obj) return toArr();
		var arr = new Array;
		for(var x in obj) arr.push(tojson(x + "") + ":" + tojson(obj[x]));
		return "{" + arr.join(",") + "}";
	}
	function toArr() {
		var arr = new Array;
		for(var i = 0; i < obj.length; i++) arr.push(tojson(obj[i]));
		return "[" + arr.join(",") + "]";
	}
	function toTime() {
		var t = new Date(obj - 0);
		var str = t.getFullYear() + "-";
		str += z(t.getMonth() + 1) + "-";
		str += z(t.getDate()) + " ";
		str += z(t.getHours()) + ":";
		str += z(t.getMinutes()) + ":";
		str += z(t.getSeconds());
		return '"' + str + '"';
	}
	function z(num) { return num < 10 ? "0" + num : num; }
}

function fromjson(str) {
	var regTag = /[\{\[\"ntf\d\.\-]/, i = 0, len = str.length;
	function newParse() {
		var s = waitStr(regTag);
		if(!s) return;
		switch(s) {
			case "{": return findObj();
			case "[": return findArr();
			case "t": return findTrue();
			case "f": return findFalse();
			case "n": return findNull();
			case '"': return findStr();
		}
		return findNum(s);
	}

	function findObj() {
		var obj = new Object;
		while(i < len) {
			var s = waitStr(/\S/);
			if(s == "}") break;
			if(s == ",") continue;
			var key = findStr();
			waitStr(/\:/);
			obj[key] = newParse();
		}
		return obj;
	}

	function findArr() {
		var arr = new Array;
		while(i < len) {
			var s = waitStr(/\S/);
			if(s == "]") break;
			if(s == ",") continue;
			i--; arr.push(newParse());
		}
		return arr;
	}

	function findTrue() { i += 3; return true; }
	function findFalse() { i += 4; return false; }
	function findNull() { i += 3; return null; }

	function findStr() {
		var s = new Array;
		while(i < len) {
			var _s = str.charAt(i++);
			if(_s == '"') break;
			if(_s == "\\") _s = strDec(str.charAt(i++));
			s.push(_s);
		}
		return s.join("");
	}

	function findNum(s) {
		while(i < len) {
			var _s = str.charAt(i++);
			if(!/[\d\.\-]/.test(_s)) break;
			s += _s;
		}
		// 上个字符非数字，重新进入匹配
		i--; return s - 0;
	}

	function waitStr(reg) {
		while(i < len) {
			var s = str.charAt(i++);
			if(reg.test(s)) return s;
		}
		return "";
	}
	
	var dic = { n: "\n", r: "\r", b: "\b", f: "\f", t: "\t", v: "\x0b" };
	function strDec(c) {
		switch(c) {
			case "x": return unescape("%" + str.slice(i, i += 2));
			case "u": return unescape("%u" + str.slice(i, i += 4));
		}
		return c in dic ? dic[c] : c;
	}
	return newParse();
}