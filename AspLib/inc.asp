<!-- #include file="core.asp" --><%
sys.debug = true;
sys.wx = { id: "wx0123456789abcdef", secret: "1234567890abcdef1234567890abcdef" };
sys.mch = { id: "123456789", key: "1234567890abcdef1234567890abcdef", cert: "LOCAL_MACHINE\\MY\\某某科技有限公司" };
sys.smtp = { host: "smtp.qq.com", user: "@qq.com", pass: "asdgkasdkgakdglsldf" };

/*
echo(boot((qstr("r") || "/Home").split("/"))); /*/
Response.Charset = "UTF-8";
try { echo(boot((qstr("r") || "/Home").split("/"))); }
catch(err) { echo(err.message); dbg().trace(err.message, db().lastSql); }
finally { closeAllDb(); dbg().appendLog(); }	// */

function me() {
	if(sys.me) return sys.me;
	var ins = sys.me = ss(sys.ns).me || new Object;
	ins.bind = function(user) { user.isLogin = true; ss(sys.ns).me = user; delete sys.me; };
	ins.lose = function() { delete ss(sys.ns).me; delete sys.me; };
	return ins;
}

function iswx() { return /MicroMessenger/i.test(env("HTTP_USER_AGENT")); }

function wxlogin(backurl, scope, codeurl) {
	if(!codeurl) codeurl = "/weixin.asp";
	ss().wxbackurl = backurl;
	// if(ss().wxinfo) return sys.onwxlogin ? sys.onwxlogin() : redir(backurl);
	ss().wxbackstate = md5(Math.random(), 16);
	var url = "https://open.weixin.qq.com/connect/oauth2/authorize?appid=" + sys.wx.id;
	url += "&redirect_uri=" + encodeURIComponent("http" + (env("HTTPS") == "on" ? "s" : "") + "://" + env("HTTP_HOST") + codeurl);
	url += "&response_type=code&scope=snsapi_" + (scope || "base") + "&state=" + ss().wxbackstate + "&connect_redirect=1#wechat_redirect";
	return redir(url);
}

function getopenid(code) {
	var url = "https://api.weixin.qq.com/sns/oauth2/access_token?appid=" + sys.wx.id;
	url += "&secret=" + sys.wx.secret + "&code=" + code + "&grant_type=authorization_code";
	var rs = fromjson(ajax(url));
	if(!rs.openid) return { err: rs.errmsg + ": " + code || "未知错误" };
	return ss().wxinfo = rs;
}

function getwxinfo(res) {
	if(res.scope != "snsapi_userinfo") return { err: "无权获取用户信息" };
	var url = "https://api.weixin.qq.com/sns/userinfo?access_token=" + res.access_token;
	var info = fromjson(ajax( url + "&openid=" + res.openid + "&lang=zh_CN")) || new Object;
	return !info.openid ? { err: info.errmsg || "获取微信资料时出现未知错误" } : info;
}

function wxcashier(fee, apivalue, backurl, goods) {
	if(fee < 1) return { err: "缺少支付费用" };
	if(!me().openid) return { err: "缺少付款人" };
	var tradeno = tojson(sys.sTime.getVarDate()).slice(3, -1).replace(/\D/g, "") + (Math.random() + "").substr(2, 4);
	var par = {
		body: goods || "收银台", attach: apivalue, detail: "{}", total_fee: fee,
		out_trade_no: tradeno, openid: me().openid, spbill_create_ip: env("REMOTE_ADDR"),
		notify_url: "http://" + env("HTTP_HOST") + backurl, nonce_str: md5(Math.random(), 16),
		appid: sys.wx.id, mch_id: sys.mch.id, device_info: "WEB", fee_type: "CNY", trade_type: "JSAPI"
	};
	par.sign = wxpaysign(par, sys.mch.key);  sys.cert = sys.mch.cert;
	var xml = ajax("https://api.mch.weixin.qq.com/pay/unifiedorder", toxml(par), "text/xml");
	var rs = fromxml(xml); delete sys.cert;
	if(rs("return_code") == "FAIL") return { err: rs("return_msg") };
	var arg = { appId: sys.wx.id, nonceStr: par.nonce_str, signType: "MD5" };
	if(!rs("prepay_id")) return { err: rs("err_code_des") };
	arg.timeStamp = (sys.sTime - 0 + "").slice(0, -3);
	arg.package = "prepay_id=" + rs("prepay_id");
	arg.paySign = wxpaysign(arg, sys.mch.key);
	return arg;
}

function wxauthpay(apiName) {
	var answer = function(code, msg) { echo(toxml({ return_code: code, return_msg: msg })); };
	var xml = new ActiveXObject("Microsoft.XmlDom");
	try { xml.load(Request); }
	catch(err) { return answer("FAIL", err.message); }
	Application("payxml") = html(xml.xml);
	var node = xml.selectNodes("/xml/*"), par = new Object;
	for(var i = 0; i < node.length; i++) par[node[i].tagName] = node[i].text;
	if(!par.sign) return answer("FAIL", "缺少支付签名");
	var sign = par.sign; delete par.sign;
	if(wxpaysign(par, sys.mch.key) != sign) return answer("FAIL", "签名校验失败");
	var rs = db().table("logins a").join("wxpaylog b on b.tradewx=@wxid").
		where("a.openid=@openid").select("a.id, b.tradewx").
		fetch([ par.transaction_id, par.openid ]);
	if(!rs || rs.tradewx) return answer("SUCCESS", "OK");
	par.sign = sign;
	db().insert("wxpaylog", {
		userid: rs.id, fee: par.total_fee, tradewx: par.transaction_id, apiname: apiName, 
		tradeno: par.out_trade_no, openid: par.openid, memo: tojson(par), apivalue: par.attach
	});
	par.userid = rs.id; par.apivalue = par.attach;
	answer("SUCCESS", "OK"); return par;
}

function wxpaysign(par, mchKey) {
	var arr = new Array;
	for(var x in par) arr.push(x + "=" + par[x]);
	arr.sort(); arr.push("key=" + mchKey);
	return md5(arr.join("&")).toUpperCase();
}

// 缓存公众号 AccessToken
function wxaccesstoken() {
	return cc("AccessToken." + sys.wx.id, function() {
		return fromjson(
			ajax("https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=" +
			sys.wx.id + "&secret=" + sys.wx.secret)
		).access_token;
	}, 7100);
}
// 缓存 JS API 票据
function wxjsapiticket() {
	return cc("JsTicket." + sys.wx.id, function() {
		var token = wxaccesstoken(); if(!token) return;
		return fromjson(ajax("https://api.weixin.qq.com/cgi-bin/ticket/getticket?access_token=" + token + "&type=jsapi")).ticket;
	}, 7100);
}

// JS API 签名
function wxjsapisign(url) {
	if(!sys.wx.id) return { err: "尚未配置 appid" };
	if(!url) return { err: "没有需要签名的网址" };
	var ticket = wxjsapiticket();
	if(!ticket) return { err: "获取 ticket 失败" };
	var arg = {
		appId: sys.wx.id,
		nonceStr: md5(Math.random(), 16),
		timestamp: (sys.sTime - 0).toString().slice(0, -3)
	};
	var arr = [
		"jsapi_ticket=" + ticket,
		"noncestr=" + arg.nonceStr,
		"timestamp=" + arg.timestamp,
		"url=" + url.split("#")[0]
	];
	arg.signature = hash("sha1", arr.join("&"));
	return arg;
}

// 访问监控
function dbg() {
	return sys.dbg || new function() {
		// 已关闭调试功能
		if(!sys.debug) return sys.dbg = { appendLog: function() {}, trace: function() {} };
		// 得到缓存数据
		if(!cc().debug) cc().debug = { last: cc().win.Array(), slow: cc().win.Array(), logs: cc().win.Array() };
		var cache = cc().debug, logs = { rows : cc().win.Array() };
		this.appendLog = function() {
			var today = sys.sTime.getDate();
			// 访问计数递增
			if(today != cache.date) {
				cache.date = today;
				cache.yesterday = ~~cache.today;
				cache.today = 0;
			}
			cache.today = -~cache.today;
			var route = get("r"), url = env("URL"), method = env("REQUEST_METHOD"), ip = env("REMOTE_ADDR");
			var time = sys.sTime.getVarDate(), exec = new Date - sys.sTime;
			// 方法，路径，路由，IP，访问时间，执行时间
			var row = [ method, url, route, ip, time, exec ];
			// 记录最新日志
			cache.last.unshift(row);
			if(cache.last.length > 100) cache.last.length = 100;
			// 记录调试信息
			if(logs.rows.length) {
				// 方法，路径，路由，时间，时长
				logs.info = [ env("REQUEST_METHOD"), env("URL"), get("r"), tojson(sys.sTime.getVarDate()).slice(1, -1), new Date - sys.sTime ];
				cache.logs.unshift(logs);
			}
			if(cache.logs.length > 100) cache.logs.length = 100;
			// 记录慢日志
			var minTime = cache.minTime || 0;
			if(exec < minTime) return;
			cache.slow.push(row);
			cache.slow.sort(function(a, b) { return b[5] - a[5]; });
			if(cache.slow.length > 100) cache.slow.length = 100;
			cache.minTime = cache.slow[ cache.slow.length - 1 ][5];
		};
		this.trace = function() {
			for(var i = 0; i < arguments.length; i++) {
				var data = arguments[i];
				logs.rows.push([ data instanceof Object ? tojson(data) : data, new Date - sys.sTime ]);
			}
		};
		sys.dbg = this;
	};
}
%>
