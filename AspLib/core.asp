<%@ Language="LiveScript" CodePage="65001" %><%
// JsAsp v1.2009.18
var sys = { sTime : new Date };

function ss(ns) {
	if(!ns) ns = "global.";
	var obj = Session(ns + "root");
	if(!obj) obj = Session(ns + "root") = new Object;
	return obj;
}

function cc(k, func, sec) {
	if(!k) return Application.StaticObjects("doc").frames.cc;
	var rs = cc();
	if(!rs.redis) rs.redis = new Object;
	var ins = rs.redis[k];
	if(!ins) ins = rs.redis[k] = new Object;
	if(!sec) sec = 0; sec *= 1000; sec = sys.sTime - sec;
	if(ins.time && (ins.time > sec)) return ins.value;
	ins.time = sys.sTime - 0; try {
	ins.value = "function" == typeof func ? func.call(ins) : func;
	} catch(err) { delete rs.redis[k]; throw err; }
	if(ins.value == ins.n) delete rs.redis[k];
	return ins.value;
}

function html(str) { return (str + "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;"); }
function form(k) { return enumReq(Request.Form, k, "form"); }
function qstr(k) { return enumReq(Request.QueryString, k, "qstr"); }
function get(k) { return qstr(k); }
function env(k) { return enumReq(Request.ServerVariables, k, "env"); }
function redir(url) { closeAllDb(); dbg().appendLog(); Response.Redirect(url); }
function lib(path) { return GetObject("script:" + Server.MapPath(path)); }
function echo(str) { Response.Write(str); }
function dump(obj) { echo(tojson(obj)); return obj; }
function toxml(obj, ele) {
	var arr = new Array;
	for(var x in obj) {
		if(obj[x] == null) obj[x] += "";
		var tag = isNaN(x) ? x : "item";
		arr.push("object" != typeof obj[x] ? 
			"<" + tag + "><![CDATA[" + obj[x] + "]]></" + tag + ">" :
			toxml(obj[x], tag)
		);
	}
	if(!ele) ele = "xml";
	return "<" + ele + ">" + arr.join("\r\n") + "</" + ele + ">"
}
function fromxml(str) {
	var dom = new ActiveXObject("Microsoft.XmlDom"); dom.loadXML(str);
	return function(path) { return !path ? str : (dom.selectSingleNode("//" + path) || {}).text; };
}

function ajax(url, data, contentType, onopen) {
	var xhr = new ActiveXObject("MsXml2.ServerXmlHttp");
	if(sys.cert) xhr.setOption(3, sys.cert);
	xhr.open(!data ? "GET" : "POST", url, true);
	if(data) xhr.setRequestHeader("Content-Type", contentType || "application/x-www-form-urlencoded");
	if("function" == typeof onopen) onopen(xhr);
	function utf(str) { return encodeURIComponent(str + ""); }
	function parseForm(data) {
		if(!data) return "";
		if("string" == typeof data) return data;
		var arr = new Array;
		for(var x in data) arr.push(utf(x) + "=" + utf(data[x]));
		return arr.join("&");
	}
	xhr.send(parseForm(data));
	xhr.waitForResponse();
	return xhr.responseText;
}

function hash(kind, str) {
	var xml = new ActiveXObject("Microsoft.XmlDom");
	var utf = new ActiveXObject("System.Text.UTF8Encoding");
	kind = kind.toUpperCase();
	var last = kind == "SHA256" ? "Managed" : "CryptoServiceProvider";
	var csp = new ActiveXObject("System.Security.Cryptography." + kind + last);
	var root = xml.createElement("x");
	root.dataType = "bin.hex";
	var bin = utf.GetBytes_4(str);
	root.nodeTypedValue = csp.ComputeHash_2(bin);
	return root.text;
}

function hash_hmac(kind, str, key, isbin) {
	var utf = new ActiveXObject("System.Text.UTF8Encoding");
	kind = kind.toUpperCase();
	var csp = new ActiveXObject("System.Security.Cryptography.HMAC" + kind);
	csp.Key = "string" == typeof key ? utf.GetBytes_4(key) : key;
	var bin = utf.GetBytes_4(str);
	bin = csp.ComputeHash_2(bin);
	if(isbin) return bin;
	var xml = new ActiveXObject("Microsoft.XmlDom");
	var root = xml.createElement("x");
	root.dataType = "bin.hex";
	root.nodeTypedValue = bin;
	return root.text;
}

function md5(str, len) { str = hash("md5", str); return len ? str.substr(Math.round((32 - len) / 2), len) : str; }

function sendmail(mail, host) {
	var smtp = host || sys.smtp;
	var cdo = Server.CreateObject("CDO.Message");
	var cfg = function(k, v) { cdo.Configuration.Fields("http://schemas.microsoft.com/cdo/configuration/" + k).Value = v; };
	cfg("sendusing", 2);
	cfg("smtpauthenticate", 1);
	cfg("smtpserver", smtp.host);
	cfg("smtpserverport", smtp.port || 25);
	cfg("smtpusessl", smtp.usessl || false);
	cfg("sendusername", smtp.user);
	cfg("sendpassword", smtp.pass);
	cdo.Configuration.Fields.Update();
	cdo.BodyPart.Charset = "UTF-8";
	cdo.Subject = mail.subject;
	cdo.To = mail.to;
	if(mail.cc) cdo.Cc = mail.cc;
	if(mail.bcc) cdo.Bcc = mail.bcc;
	cdo.From = mail.from;
	cdo.HtmlBody = mail.body;
	try{ cdo.Send(); }
	catch(err){ return err.message; }
	return "OK";
}

function enumReq(req, k, ns) {
	if(k) return req(k).Item;
	if(sys[ns]) return sys[ns];
	var obj = sys[ns] = new Object;
	obj.toString = function() { return tojson(obj); };
	var enm = new Enumerator(req);
	while(!enm.atEnd()) { var x = enm.item(); obj[x] = req(x).Item; enm.moveNext(); }
	return obj;
}
%><script src="db.js" runat="server" language="livescript"></script>