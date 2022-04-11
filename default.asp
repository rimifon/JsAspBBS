<!-- #include virtual="/AspLib/api.asp" --><%
function boot(route) {
	sys.name = "JsAspBBS";
	sys.res = "res/bbs/";
	sys.dbPath = "App_Data/JsAspBBS.sdf";
	sys.ns = "JsAspBBS";
	sys.onerror = catchErr;
	var roles = [ "客人", "普通会员", "认证会员", "论坛副版主", "论坛版主", "分类区版主", "论坛总版主", "论坛坛主" ];
	var site = initSite();
	return apidoc({
		// 论坛首页
		index: function() {
			sys.online.setWeiZhi("/", "论坛首页", ss().sessId);
			var forums = cc(sys.ns + "Home", function() {
				var rows = db().table("forums a").where("a.pid=0 and a.state=1").
					join("forums b on b.pid=a.forumid and b.state=1").
					join("topic c on c.forumid=b.forumid and c.posttime>=convert(nchar(10), getdate(), 20)").	// 统计各版块当天的贴子数
					select("a.forumid as pid, b.forumid, count(c.topicid) as topicday").
					groupby("a.forumid, b.forumid").astable("a").join("forums b on b.forumid=a.forumid").
					join("reply c on c.replyid=b.replyid").join("topic d on d.topicid=c.topicid").
					join("users e on e.userid=c.userid").join("forums f on f.forumid=a.pid").select(
						"a.*, b.nick, b.intro, b.topicnum, b.replynum, d.title, c.topicid, c.replytime, e.nick as zuozhe, f.nick as pnick"
					).orderby("f.sort, f.forumid, b.sort, b.forumid").query();
				var catas = new Array, obj = new Object, banzhu = new Object;
				db().table("banzhu a").join("users b on b.userid=a.userid").
					select("a.forumid, b.userid, b.nick").query().forEach(function(x) {
						if(!banzhu[x.forumid]) banzhu[x.forumid] = new Array;
						banzhu[x.forumid].push(x);
					});
				rows.forEach(function(x) {
					if(!obj[x.pid]) {
						obj[x.pid] = { list: new Array, pid: x.pid, nick: x.pnick };
						catas.push(obj[x.pid]);
					}
					if(!x.forumid) return;
					obj[ x.pid ].list.push(x);
					x.banzhu = banzhu[ x.forumid ] || new Array;
				});
				// 数组转 json 后缓存，读取时会更快
				return tojson(catas);
			}, 9);
			forums = fromjson(forums);
			var online = fromjson(sys.online.data());
			online.users.guest = online.users.all - online.users.reg;
			online.rows.sort(function(a, b) { return b.eTime - a.eTime; });
			online.rows.forEach = function(f) { for(var i = 0; i < this.length; i++) f(this[i], i); };
			var onlineInfo = function(x) {
				return [
					"当前位置：" + x.weizhi,
					"来访时间：" + tojson(new Date(x.sTime).getVarDate()).slice(1, -1),
					"活动时间：" + tojson(new Date(x.eTime).getVarDate()).slice(1, -1),
					"操作系统：" + x.xitong,
					"ＩＰ地址：" + ( me().roleid > 5 ? x.ip : "已设置保密"),
					"点击次数：" + x.hits
				].join("\r\n");
			}
			if(online.users.all > ~~site.topOnline) {
				// 更新最高在线
				site.topOnline = online.users.all;
				site.topOntime = sys.sTime - 0;
			}
			return master(function() { %><!-- #include file="views/index.html" --><% });
		}

		// 登录论坛
		,login: function() {
			sys.title = "登录论坛 - ";
			sys.online.setWeiZhi("login", "登录论坛", ss().sessId);
			return master(function() { %><!-- #include file="views/login.html" --><% });
		}

		// 退出登录
		,logout: function() {
			sys.onlineMe.roleid = 0;
			sys.onlineMe.nick = "客人";
			me().lose.call(0); redir(".");
		}

		// 用户注册
		,register: function() {
			sys.title = "注册新用户 - ";
			sys.online.setWeiZhi("register", "注册账号", ss().sessId);
			return master(function() { %><!-- #include file="views/register.html" --><% });
		}

		// 帖子列表
		,forum: function() {
			var par = { forumid: ~~route[1] }, page = ~~route[2];
			var forum = db().fetch("select * from forums where forumid=@forumid and state=1 and pid>0", par);
			if(!forum) return errpage("没有您访问的版块");
			sys.title = forum.nick + " - ";
			var rows = db().table("topic").select("topicid").where("forumid=@forumid").
				page("ding desc, coalesce(replytime, posttime) desc", 25, page, par).astable("a").
				join("topic b on b.topicid=a.topicid").join("users c on c.userid=b.userid").join("users d on d.userid=b.replyid").
				select("b.*, c.nick, d.nick as reply").orderby("b.ding desc, coalesce(replytime, posttime) desc").query();
			var pager = db().pager;
			sys.online.setWeiZhi("forum/" + par.forumid, forum.nick, ss().sessId);
			var online = fromjson(sys.online.data("forum/" + par.forumid));
			online.users.guest = online.rows.length - online.users.reg;
			online.rows.sort(function(a, b) { return b.eTime - a.eTime; });
			var onlineInfo = function(x) {
				return [
					"当前位置：" + x.weizhi,
					"来访时间：" + tojson(new Date(x.sTime).getVarDate()).slice(1, -1),
					"活动时间：" + tojson(new Date(x.eTime).getVarDate()).slice(1, -1),
					"操作系统：" + x.xitong,
					"ＩＰ地址：" + ( me().roleid > 5 ? x.ip : "已设置保密"),
					"点击次数：" + x.hits
				].join("\r\n");
			}
			var isBZ = isBanZhu(forum.forumid);
			return master(function() { %><!-- #include file="views/forum.html" --><% });
		}

		// 查看帖子
		,topic: function() {
			var par = { topicid: ~~route[1] }, page = ~~route[2];
			var topic = db().table("topic a").join("forums b on b.forumid=a.forumid").
				where("a.topicid=@topicid and b.state=1").select("a.*, b.nick").fetch(par);
			if(!topic) return errpage("主题不存在，或暂时不可访问。");
			sys.title = topic.title + " - ";
			var rows = db().table("reply").select("replyid").where("topicid=@topicid").page("replyid", 12, page, par).
				astable("a").join("reply b on b.replyid=a.replyid").join("users c on c.userid=b.userid").
				select("b.*, c.nick, c.icon, c.jifen, c.fatie, c.regtime, c.lasttime, c.roleid, c.diqu").query();
			var pager = db().pager;
			var lou = (pager.curpage - 1) * pager.pagesize + 1;
			db().query("update topic set pv=pv+1 where topicid=@topicid", par);
			var jifen = jifenHelper();	// 根据积分解析称号
			// 暂定 1000 积分 为满分
			var getPer = function(score){ return Math.round(score * 100 / Math.max(1e3, score)); };
			sys.online.setWeiZhi("forum/" + topic.forumid, "[" + topic.nick + "]" + topic.title, ss().sessId);
			var isBZ = isBanZhu(topic.forumid);
			// if(!me().isLogin) dbg().trace(env("REMOTE_ADDR") + "在偷偷查看《" + topic.title + "》");
			return master(function() { %><!-- #include file="views/topic.html" --><% });
		}

		// 论坛 API 接口定义
		,api: {
			Memo: [ "* JsASP 论坛 API 接口", "* 发帖 +5 积分，评论 +2 积分，登录 +1 积分" ]

			,RegisterDoc: [ "用户注册", "user, pass", "第一个注册的用户将自动成为论坛坛主。" ]
			,register: function() {
				// 用户名不可包含<">
				var par = { nick: form("user") };
				if(!par.nick) return { err: "缺少用户名" };
				if(/[<">]/.test(par.nick)) return { err: "非法的用户名/昵称" };
				if(db().scalar("select userid from users where nick=@nick", par)) return { err: "此用户名已经被注册了" };
				par.pass = md5(form("pass") || "a", 16);
				par.lasttime = sys.sTime.getVarDate();
				par.lastip = env("REMOTE_ADDR");
				db().insert("users", par);
				var uid = db().scalar("select @@identity");
				// 如果新用户ID为 1，则自动更新权限为坛主
				if(uid < 2) db().update("users", { roleid: 7 }, { userid: 1 });
				// 自动登录
				var user = db().fetch("select * from users where userid=@userid", { userid: uid });
				sys.onlineMe.nick = user.nick;
				sys.onlineMe.roleid = user.roleid;
				me().bind.call(0, user);
				dbg().trace("用户『" + user.nick + "』注册成功");
				return { msg: "注册成功" };
			}

			,LoginDoc: [ "登录接口", "user, pass" ]
			,login: function() {
				var par = { user: form("user") || "", pass: md5(form("pass") || "a", 16) };
				if(!par.user) return { err: "未提供用户名" };
				var user = db().fetch("select * from users where nick=@user and pass=@pass", par);
				dbg().trace(par.user + " 登录" + (!user ? "失败[登录IP: " + env("REMOTE_ADDR") + "]" : "成功"));
				if(!user) return { err: "登录失败" };
				user.lastip = env("REMOTE_ADDR");
				user.lasttime = sys.sTime.getVarDate();
				user.jifen++;
				db().query("update users set lastip=@lastip, lasttime=@lasttime, jifen=jifen+1 where userid=@userid", { lastip: user.lastip, lasttime: user.lasttime, userid: user.userid });
				me().bind.call(0, user);
				sys.onlineMe.nick = user.nick;
				sys.onlineMe.roleid = user.roleid;
				return { msg: "登录成功" };
			}

			// 发帖
			,TopicAddDoc: [ "发表帖子", "forumid, title, message, [user], [pass]" ]
			,topicadd: function() {
				if(form("user")) {
					var rs = this.login();
					if(rs.err) return rs;
				}
				if(!me().isLogin) return { err: "您未登录，或登录已过期，发帖失败。" };
				if(!form().title) return { err: "请填写主题" };
				if(!form().message) return { err: "请填写帖子内容" };
				var forumid = ~~form().forumid;
				if(!forumid) return { err: "缺少版块ID" };
				form().title = html(form().title);
				form().message = html(form().message);
				if(form().message.length > 4000) return { err: "内容太长，请尝试减少内容。" };
				// 插入主题表
				db().insert("topic", { title: form().title, forumid: forumid, userid: me().userid });
				var topicid = db().scalar("select @@identity");
				// 插入评论表
				db().insert("reply", { topicid: topicid, userid: me().userid, ip: env("REMOTE_ADDR"), message: form().message });
				var replyid = db().scalar("select @@identity");
				// 更新发帖量
				db().query("update forums set topicnum=topicnum+1, replyid=@replyid where forumid=@forumid", { replyid: replyid, forumid: forumid });
				db().query("update users set fatie=fatie+1, jifen=jifen+5 where userid=@userid", { userid: me().userid });
				me().fatie++; me().jifen += 5;
				dbg().trace(me().nick + "发表了帖子《" + form().title + "》");
				return { msg: "发帖成功", topicid: topicid };
			}

			// 添加评论
			,ReplyAddDoc: [ "添加评论", "topicid, message, [user], [pass]" ]
			,replyadd: function() {
				if(form("user")) {
					var rs = this.login();
					if(rs.err) return rs;
				}
				if(!me().isLogin) return { err: "您未登录，或登录已过期，发帖失败。" };
				var par = { topicid: ~~form("topicid"), message: html(form("message")), ip: env("REMOTE_ADDR"), userid: me().userid };
				if(!par.message.replace(/\s/g, "")) return { err: "请填写帖子内容" };
				if(par.message.length > 4000) return { err: "内容太长，请尝试减少内容。" };
				var topic = db().table("topic a").join("forums b on b.forumid=a.forumid").
					where("a.topicid=@topicid").select("a.forumid, a.title").fetch({ topicid: par.topicid });
				if(!topic) return { err: "回复的帖子不存在" };
				db().insert("reply", par);
				var replyid = db().scalar("select @@identity");
				db().query("update forums set replynum=replynum+1, replyid=@replyid where forumid=@forumid", { replyid: replyid, forumid: topic.forumid });
				db().query("update topic set replynum=replynum+1, replytime=getdate(), replyid=@userid where topicid=@topicid", { userid: me().userid, topicid: par.topicid });
				db().query("update users set jifen=jifen+2 where userid=@userid", { userid: me().userid });
				dbg().trace(me().nick + "评论了帖子《" + topic.title + "》");
				me().jifen += 2; return { msg: "评论成功" };
			}

			// 删除评论
			,ReplyDropDoc: [ "删除评论", "replyid" ]
			,replydrop: function() {
				if(!me().isLogin) return { err: "您尚未登录" };
				var par = { replyid: ~~form("replyid") };
				var reply = db().table("reply a").join("reply b on b.topicid=a.topicid").groupby("a.replyid").
					where("a.replyid=@replyid").select("a.replyid, min(b.replyid) as minid").astable("a").
					join("reply b on b.replyid=a.replyid").join("topic c on c.topicid=b.topicid").
					select("a.*, b.userid, b.topicid, c.forumid").fetch(par);
				if(!reply) return { err: "此评论不存在" };
				if(reply.userid != me().userid && !isBanZhu(reply.forumid)) return { err: "您没删除此评论的权限" };
				if(reply.replyid == reply.minid) return this.topicdrop(reply.topicid);
				db().query("delete from reply where replyid=@replyid", par);
				db().query("update topic set replynum=replynum-1 where topicid=@topicid", { topicid: reply.topicid });
				db().query("update forums set replynum=replynum-1 where forumid=@forumid", { forumid: reply.forumid });
				return { msg: "评论删除成功" };
			}

			,TopicDropDoc: [ "删除主题", "topicid" ]
			,topicdrop: function(topicid) {
				if(!me().isLogin) return { err: "您尚未登录" };
				var par = { topicid: topicid || ~~form().topicid };
				var topic = db().fetch("select userid, forumid, replynum from topic where topicid=@topicid", par);
				if(!topic) return { err: "删除的话题不存在" };
				if(me().userid != topic.userid && !isBanZhu(topic.forumid)) return { err: "您没有权限删除这个帖子。" };
				db().query("delete from reply where topicid=@topicid", par);
				db().query("delete from topic where topicid=@topicid", par);
				db().query("update forums set replynum=replynum-@replynum, topicnum=topicnum-1 where forumid=@forumid", {
					replynum: topic.replynum, forumid: topic.forumid
				});
				return { msg: "主题删除成功" };
			}

			,ReplyLoadDoc: [ "加载评论", "replyid", "用于编辑评论" ]
			,replyload: function() {
				if(!me().isLogin) return { err: "您尚未登录或登录已超时" };
				var par = { replyid: ~~form("replyid") };
				var reply = db().table("reply a").join("topic b on b.topicid=a.topicid").
					where("a.replyid=@replyid").select("a.message, a.userid, b.forumid").fetch(par);
				if(!reply) return { err: "您要编辑的评论不存在" };
				if(reply.userid != me().userid && !isBanZhu(reply.forumid)) return { err: "您没有此评论的编辑权限。" };
				return reply;
			}

			,ReplyEditDoc: [ "编辑/保存评论", "replyid, message" ]
			,replyedit: function() {
				if(!me().isLogin) return { err: "您尚未登录或登录已超时" };
				var message = form("message") || "";
				if(!message.replace(/\s/g, "")) return { err: "请填写评论内容" };
				var par = { replyid: ~~form("replyid") };
				var reply = db().table("reply a").join("topic b on b.topicid=a.topicid").
					where("a.replyid=@replyid").select("a.message, a.userid, b.forumid").fetch(par);
				if(!reply) return { err: "您要编辑的评论不存在" };
				if(reply.userid != me().userid && !isBanZhu(reply.forumid)) return { err: "您没有此评论的编辑权限。" };
				db().update("reply", { message: html(message) }, par);
				return { msg: "编辑成功" };
			}

			,TopicDingDoc: [ "帖子固定/取消操作", "topicid, state" ]
			,topicding: function() {
				if(!me().isLogin) return { err: "请登录后操作" };
				if(me().roleid < 3) return { err: "没有权限执行此操作" };
				var par = { topicid: ~~form("topicid") };
				var topic = db().fetch("select forumid from topic where topicid=@topicid", par);
				if(!topic) return { err: "操作的帖子不存在" };
				if(!isBanZhu(topic.forumid)) return { err: "没有权限执行此操作" };
				db().update("topic", { ding: ~~form("state") }, par);
				return { msg: "操作完成" };
			}

			,TopicJingDoc: [ "帖子加精/取消操作", "topicid, state" ]
			,topicjing: function() {
				if(!me().isLogin) return { err: "请登录后操作" };
				if(me().roleid < 3) return { err: "没有权限执行此操作" };
				var par = { topicid: ~~form("topicid") };
				var topic = db().fetch("select forumid from topic where topicid=@topicid", par);
				if(!topic) return { err: "操作的帖子不存在" };
				if(!isBanZhu(topic.forumid)) return { err: "没有权限执行此操作" };
				db().update("topic", { jing: ~~form("state") }, par);
				return { msg: "操作完成" };
			}

			,UploadDoc: [ "上传接口", "file" ]
			,upload: function() {
				if(!me().isLogin) return { err: "需要登录" };
				if(me().jifen < 50 && me().roleid < 2) return { err: "您的积分不到50，暂不允许上传文件" };
				var up = lib("/AspLib/lib/FyUpload.sct");
				up.Filter = "jpg|jpg|png|gif|zip|rar|txt";
				up.MaxSize = 1024 * 1024;	// 允许 1M
				up.Charset = "UTF-8"; up.ReadForm(2e5);
				var file = up.Form("file");
				if(!file || !file.SourceName) return { err: "未上传文件" };
				var time = tojson(sys.sTime.getVarDate()).replace(/\D/g, "");
				var path = "Upload/JsAspBBS/" + time.substr(2, 4) + "/" + time.substr(6, 2);
				up.EnsurePath(path);	// 确保目录存在
				file.SaveName = time.slice(8) + Math.random().toFixed(3).slice(1);
				up.SaveFile(path); up.Dispose();
				if(file.Message) return { err: file.Message };
				return { path: path + "/" + file.FileName };
			}
		}

		// 论坛管理端
		,admin: {
			forum: function() {
				if(~~me().roleid < 7) return errpage("您没有权限执行此操作");
				sys.title = "编辑板块 - ";
				var catas = db().query("select forumid, nick from forums where pid=0 order by sort, forumid");
				var par = { forumid: ~~route[2] };
				var forum = par.forumid ? db().fetch("select * from forums where forumid=@forumid", par) : { forumid: 0 };
				if(!forum) return errpage("此板块已不存在");
				var act = function(cid, fid) { return cid == fid ? cid + '" selected="true' : cid; };
				return master(function(){ %><!-- #include file="views/admin/forum.html" --><% });
			}

			// 管理 API 接口
			,api: {
				Memo: [ "管理端 API 接口 " + "[返回论坛]".link(".") ]

				,SetSiteNameDoc: [ "设置网站名称", "sitename, weiboname", "sitename: 网站名称", "weiboname: 微博版式名称" ]
				,setsitename: function() {
					if(~~me().roleid < 7) return { err: "没有设置权限" };
					var site = fromjson(db().scalar("select * from site"));
					site.sitename = form("sitename");
					site.weiboname = form("weiboname");
					db().query("update site set cfg=@cfg", { cfg: tojson(site) });
					return site;
				}

				,BanZhuAddDoc: [ "添加版主", "forumid, userid", "forumid: 版块 ID", "userid: 用户 ID" ]
				,banzhuadd: function() {
					if(~~me().roleid < 7) return { err: "没有操作权限" };
					var par = { forumid: ~~form().forumid, userid: ~~form().userid };
					var user = db().table("users a").join("banzhu b on b.forumid=@forumid and b.userid=a.userid").
						where("a.userid=@userid").select("a.nick, a.roleid, b.userid").fetch(par);
					if(!user) return { err: "用户不存在" };
					if(user.userid) return { err: "该用户已经是版主了" };
					db().insert("banzhu", par);
					if(user.roleid < 4) db().update("users", { roleid: 4 }, { userid: par.userid });
					return user;
				}

				,BanZhuDropDoc: [ "删除斑竹", "forumid, userid", "forumid: 版块 ID", "userid: 用户 ID" ]
				,banzhudrop: function() {
					if(~~me().roleid < 7) return { err: "没有操作权限" };
					var par = { forumid: ~~form().forumid, userid: ~~form().userid };
					db().query("delete from banzhu where forumid=@forumid and userid=@userid", par);
					return { msg: "操作完成" };
				}

				,UserQueryDoc: [ "用户查询", "[user], page", "user 可以为 userid，也可以为用户昵称" ]
				,userquery: function() {
					var users = db().table("users"), par = new Object, page = ~~form("page") || 1;
					if(form("user")) {
						par.user = form("user");
						users.where(isNaN(par.user) ? "charindex(@user, nick)>0" : "userid=@user");
					}
					var res = users.page("userid desc", 10, page, par).select("userid, nick, jifen, fatie, roleid, regtime, lasttime").query();
					return { list: res, pager: db().pager };
				}

				// 用户权限设置
				,UserRoleDoc: [ "用户权限设置", "userid, roleid", "userid: int, 用户 ID", "roleid: int, 权限 ID" ]
				,userrole: function() {
					if(~~me().roleid < 7) return { err: "没有操作权限" };
					var par = { userid: ~~form().userid, roleid: ~~form().roleid };
					db().update("users", { roleid: par.roleid }, { userid: par.userid });
					return { msg: "操作完成" };
				}

				// 编辑帖子标题
				,EditTitleDoc: [ "编辑帖子标题，或转移帖子到其他版块", "topicid, title, forumid", "topicid: int, 帖子 ID", "title: string, 标题", "forumid: int, 版块 ID" ]
				,edittitle: function() {
					if(~~me().roleid < 7) return { err: "没有操作权限" };
					var par = new Object, where = { topicid: ~~form("topicid") };
					if(form("title")) par.title = form("title");
					if(form("forumid")) par.forumid = ~~form("forumid");
					if(!par.title && !par.forumid) return { err: "没有操作内容" };
					if(par.forumid) {
						var topic = db().table("topic").where("topicid=@topicid").fetch(where);
						if(!topic) return { err: "帖子不存在" };
						// 减少原版块的贴子数和回复数
						db().query("update forums set topicnum=topicnum-1, replynum=replynum-@replynum where forumid=@forumid", { replynum: topic.replynum, forumid: topic.forumid });
						// 增加新版块的贴子数和回复数
						db().query("update forums set topicnum=topicnum+1, replynum=replynum+@replynum where forumid=@forumid", { replynum: topic.replynum, forumid: par.forumid });
					}
					db().update("topic", par, where);
					return { msg: "操作完成" };
				}

				,ForumSaveDoc: [ "保存板块信息", "[forumid], pid, nick, intro, sort", "点此进入添加版块界面".link("?r=admin/forum/0") ]
				,forumsave: function() {
					if(~~me().roleid < 7) return { err: "没有权限" };
					var par = { nick: form("nick"), intro: form("intro"), pid: form("pid"), sort: form("sort") };
					var forumid = ~~form("forumid");
					if(!forumid) return db().insert("forums", par), { msg: "创建成功" };
					return db().update("forums", par, { forumid: forumid }), { msg: "保存成功" };
				}

				,ForumDropDoc: [ "删除版块", "forumid", "坛主可以删除空的版块" ]
				,forumdrop: function() {
					if(~~me().roleid < 7) return { err: "没有权限" };
					var par = { forumid: ~~form("forumid") };
					if(db().fetch("select top 1 1 from topic where forumid=@forumid", par)) return { err: "版块存在帖子，不可直接删除。" };
					if(db().fetch("select top 1 1 from forums where pid=@forumid", par)) return { err: "存在子版块，不可直接删除。" };
					db().query("delete from forums where forumid=@forumid", par);
					return { msg: "删除成功" }
				}
			}
		}

		// 微博模块
		,weibo: {
			Memo: [ "微博模块 | " + "点击访问".link("weibo/"), "微博模块是一个可以发布微博的模块，可以让用户发布微博，并且可以让用户关注其他用户。" ]

			// 微博首页
			,HomeDoc: [ "微博首页" ]
			,home: function() {
				sys.ismaster = true;
				// 获取论坛版块名称列表
				var forums = db().table("forums a").join("forums b on b.forumid=a.pid").
					select("a.forumid, a.pid, a.nick").where("a.pid>0").orderby("b.sort, a.sort").query();
				// 获取用户数和帖子数
				var total = cc(sys.ns + ".weibo.total", function() {
					var rs = new Object;
					rs.users = db().scalar("select count(0) from users");
					rs.topics = db().table("forums").select("sum(topicnum)").scalar();
					return rs;
				}, 30);
				var list = this.topiclist();
				return { forums: forums, topics: list.topics, sitename: site.weiboname || sys.name, total: total, dings: list.dings };
			}

			// 论坛帖子列表
			,TopicListDoc: [ "论坛帖子列表", "forumid, lastid", "forumid: int, 版块ID", "lastid: int, 可以为空", "第 11 条为下页第一条" ]
			,topiclist: function() {
				sys.online.setWeiZhi("/weibo", "查看微博", ss().sessId);
				var forumid = ~~form("forumid"), lastid = ~~form("lastid");
				var query = db().table("topic"), where = new Array, par = new Object, where2 = new Array;
				if(forumid) {
					where.push("forumid=@forumid");
					where2.push("forumid=@forumid");
					par.forumid = forumid;
				}
				where2.push("ding=1");
				// 不存在分页时查询置顶内容
				var dings = !lastid ? db().table("topic").where(where2.join(" and ")).select("top 4 topicid, title").orderby("topicid desc").query(par) : [];
				if(lastid) {
					where.push("topicid<=@lastid");
					par.lastid = lastid;
				}
				if(where.length) query.where(where.join(" and "));
				// 统计帖子评论数
				var topics = query.orderby("topicid desc").select("top 11 topicid").astable("a").
					// 取第一条评论为帖子内容
					join("reply b on b.topicid=a.topicid").groupby("a.topicid").select("a.topicid, min(b.replyid) as replyid").
					astable("a").join("topic b on b.topicid=a.topicid").join("users c on c.userid=b.userid").
					join("forums d on d.forumid=b.forumid").join("reply e on e.replyid=a.replyid").orderby("a.topicid desc").
					select("a.*, b.title, b.pv, b.replynum, b.posttime, b.pv, c.nick, c.icon, d.nick as forumname, e.replyid, e.message").query(par);
				return { topics: topics, dings: dings };
			}

			// 评论列表
			,RepliesDoc: [ "评论列表", "topicid, firstid, [lastid]", "topicid: int, 帖子ID", "firstid: int, 排除回复的id", "lastid: int, 可以为空", "第 11 条为下页第一条" ]
			,replies: function() {
				var par = { topicid: ~~form("topicid") };
				// 获取主题名称，板块名称，登记用户当前位置，并且增加主题 PV
				var topic = db().table("topic a").join("forums b on b.forumid=a.forumid").
					select("a.topicid, a.forumid, a.title, b.nick").
					where("a.topicid=@topicid").fetch(par);
				if(!topic) return { err: "主题不存在" };
				sys.online.setWeiZhi("forum/" + topic.forumid, "[微博]" + topic.title, ss().sessId);
				db().query("update topic set pv=pv+1 where topicid=@topicid", par);
				// 获取回复列表
				var where ="a.topicid=@topicid and a.replyid!=@firstid";
				par.firstid = ~~form("firstid");
				var lastid = ~~form("lastid");
				if(lastid) { where += " and a.replyid<=@lastid"; par.lastid = lastid; }
				var replies = db().table("reply a").join("users b on b.userid=a.userid").
					where(where).select("top 11 a.replyid, a.message, a.replytime, b.nick, b.icon").
					orderby("a.replyid desc").query(par);
				return { replies: replies, userid: ~~me().userid };
			}
		}
	}, route);
}

// 母版页
function master(func) {
	sys.ismaster = true;	// 标识进入模板页了，如果页面出错，不可使用模板页返回错误
	%><!-- #include file="views/master.html" --><%
}

// 错误页
function errpage(message, title) {
	if(!title) title = "错误提示";
	sys.title = title + " - ";
	return master(function() { %><!-- #include file="views/errpage.html" --><% });
}

// 生成分页
function makePager(pager, url) {
	var cur = pager.curpage, total = pager.pagenum;
	if(!cur) return;
	var arr = [ (cur + "").bold() ], x = 0;
	var link = function(id) { return (id + "").link(url + id) };
	// cur 的左边允许出现两个
	for(var i = 0; i < 2; i++) {
		x = cur - 1 - i;
		if(x < 1) break;
		arr.unshift(link(x));
	}
	if(x > 3) arr.unshift("<span>…</span>");
	if(x == 3) arr.unshift(link(2));
	if(x > 1) arr.unshift(link(1));
	// cur 的右边边允许出现两个
	for(var i = 0; i < 2; i++) {
		x = cur + 1 + i;
		if(x > total) break;
		arr.push(link(x));
	}
	if(x < total - 2) arr.push("<span>…</span>");
	if(x == total - 2) arr.push(link(total - 1));
	if(x < total) arr.push(link(total));
	return arr.join("\r\n");
}

// 论坛帖子格式化
function fmtMsg(str) {
	var str = str || "", arrCode = new Array;
	str = str.replace(/\[html\]([\s\S]+?)\[\/html\]/gi, function(txt, code) {
		arrCode.push(code);
		return "[html=\x01]";
	});
	str = str.replace(/\t/g, "    ").replace(/  /g, "&nbsp; ").replace(/\r?\n/g, "<br />\r\n").
		replace(/\[(image|upload)=([^\]]+)\]/g, function(src, $1, $2) {
			var file = $2.split("|");
			return $1 == "image" ? '<div><a href="' + file[0] + '" target="_blank"><img src="' + file[0] + '" alt="' + html(file[1]) + '" /></a></div>'
				: ('<a href="' + file[0] + '" class="attach" target="_blank">' + file[1] + '</a>(' + file[2] + ')');
		});
	return str.replace(/\[html=\x01\]/g, function() {
		return '<div class="code"><textarea>' + arrCode.shift() + '</textarea><p class="tr">[您可以先修改代码再运行] <input type="button" value="执行代码" onclick="runcode(parentNode)" /></p></div>';
	});
}

function jifenHelper() {
	// 获取论坛称号
	var scores = [ 12, 50, 80, 150, 250, 400, 700, 1500, 2500, 5000, 8000, 12000, 2e4, 3e4, 5e4, 1e5, 9e5 ];
	var nicks = "新手上路，骑士，圣骑士，精灵，精灵王，风云使者，光明使者，天使，大天使，精灵使，法师，大法师，法王，老法王，天神，天王，法老".split("，");
	function getNick(jifen, roleid) {
		if(roleid > 6) return "究级天王[荣誉]";
		if(roleid > 5) return "终极天王[荣誉]";
		for(var i = 0; i < scores.length; i++) {
			if(jifen < scores[i]) return nicks[i];
		}
		return "法老";
	};
	return { getNick: getNick };
}

function isBanZhu(forumid, userid) {
	if(!me().isLogin) return false;
	// 判断是否斑竹
	if(me().roleid < 4) return false;
	if(me().roleid > 5) return true;
	return db().scalar(
		"select 1 from banzhu where forumid=@forumid and userid=@userid",
		{ forumid: forumid, userid: userid || me().userid }
	) == 1;
}

function initSite() {
	// 从数据库加载网站配置
	var site = cc("Site", function() {
		try {
			var rs = fromjson(db().table("site").scalar());
			if(this.value) {
				// 每 9 秒同步一次 PV 值到数据库
				rs.pv = this.value.pv;
				rs.uv = this.value.uv;
				rs.topOnline = this.value.topOnline;
				rs.topOntime = this.value.topOntime;
				db().query("update site set cfg=@cfg", { cfg: tojson(rs) });
			}
			return rs;
		} catch(err) { return catchErr(err); }
	}, 9);
	if(!site) { closeAllDb(); return Response.End(); }
	site.pv = -~site.pv;
	sys.name = site.sitename;
	sys.online = initOnline();
	if(!ss().sessId) ss().sessId = Session.SessionID;
	var mine = sys.online.getUser(ss().sessId);
	sys.onlineMe = mine;
	if(mine.ip) return site;
	site.uv = -~site.uv;
	// 初始化新用户
	mine.nick = me().nick || "客人";
	mine.ip = env("REMOTE_ADDR");
	mine.roleid = me().roleid || 0;
	mine.weizhi = "论坛首页";
	mine.path = "/";
	mine.xitong = (function() {
		var ua = env("HTTP_USER_AGENT") || "No User-Agent";
		var test = ua.match(/(\w+)[\s\-]?(?:bot|(?:web )?spider)/i);
		if(test) return mine.nick = test[1] + " 爬虫";
		test = ua.match(/android|iphone|ipad/i);
		if(test) return test[0];
		test = ua.match(/windows|macintosh|linux|ios/i);
		if(test) return test[0];
		dbg().trace("IP：" + env("REMOTE_ADDR"), env("HTTP_REFERER") || env("HTTP_USER_AGENT"));
		return "采集工具";
	})();
	return site;
}

function initOnline() {
	// cc().win.JsAspBBSOnline = null;
	if(cc().win.JsAspBBSOnline) return cc().win.JsAspBBSOnline;
	var func = cc().win.Function("return " + function() {
		var ins = new Object, data = new Object;
		var life = 20 * 6e4;	// 20分钟生存周期
		ins.getUser = function(sessId) {
			if(data[sessId]) return data[sessId];
			var user = data[sessId] = { sTime: new Date - 0, eTime: new Date - 0, sessId: sessId, hits: 0 };
			var offline = function() {
				var expr = new Date - user.eTime;
				if(expr >= life) { delete data[sessId]; return; }
				// 用户有活动？(20 - 静止时间)分钟后再看看。
				user.timer = setTimeout(offline, life - expr);
			};
			user.timer = setTimeout(offline, life);
			return user;
		};
		ins.filter = function(f) {
			var arr = new Array;
			for(var x in data) {
				if(f(data[x])) arr.push(data[x]);
			}
			return arr;
		};
		ins.data = function(path) {
			var arr = new Array, users = { all: 0, reg: 0 };
			for(var x in data) {
				users.all++;
				if(path && path != data[x].path) continue;
				// 仅首页和指定页统计当前已注册人数
				if(data[x].roleid > 0) users.reg++;
				arr.push(data[x]); 
			}
			return JSON.stringify({ rows: arr, users: users });
		};
		ins.setWeiZhi = function(path, weizhi, sessId) {
			var user = data[sessId];
			if(!user) return;
			user.eTime = new Date - 0;
			user.weizhi = weizhi;
			user.path = path;
			user.hits++;
		};
		return self.JsAspBBSOnline = ins;
	});
	return func()();
}

// 页面出错处理
function catchErr(err) {
	dbg().trace({ err: err.message || "未知错误", cmd: db().lastSql });
	// master 出错时直接返回 json 错误
	if(err.number != -2147217865) return sys.ismaster ? tojson({ err: err.message, cmd: db().lastSql }) : errpage(err.message, "请求出现意外");
	var tables = db().table("information_schema.tables").query();	// 判断数据库是不是已经初始化
	if(tables.length) return sys.ismaster ? tojson({ err: err.message, cmd: db().lastSql }) : errpage(err.message, "请求出现意外");
	// 初始化论坛参数
	db().create("site", [ "cfg nvarchar(4000)" ]);
	db().insert("site", { cfg: tojson({ sitename: sys.name }) });
	// 初始化用户表
	db().create("users", [
		[ "userid int", null, true ], "nick nvarchar(32), pass nchar(16), icon nvarchar(254), lasttime datetime, lastip nvarchar(48)",
		[ "regtime datetime", "getdate()" ], [ "fatie int", 0 ], [ "jifen int", 0 ], [ "roleid int", 1 ], "diqu nvarchar(16)"
	]);
	db().query("create unique index users_nick on users(nick)");
	// 初始化论坛表
	db().create("forums", [
		[ "forumid int", null, true ], "pid int, nick nvarchar(32), intro nvarchar(254), sort int",
		[ "topicnum int", 0 ], "replyid int", [ "replynum int", 0 ], [ "state int", 1 ]
	]);
	// 初始化版主表
	db().create("banzhu", [ "forumid int, userid int" ]);
	db().query("create index banzhu_forumid on banzhu(forumid)");
	// 初始化主题表
	db().create("topic", [
		[ "topicid int", null, true ], "forumid int, title nvarchar(254), userid int, replytime datetime, replyid int",
		[ "pv int", 0 ], [ "replynum int", 0 ], [ "posttime datetime", "getdate()" ], [ "ding tinyint", 0 ], [ "jing tinyint", 0 ]
	]);
	db().query("create index topic_forumid on topic(forumid)");
	// 初始化评论表
	db().create("reply", [
		[ "replyid int", null, true ], "topicid int, userid int, ip nvarchar(48), message nvarchar(4000)",
		[ "replytime datetime", "getdate()" ]
	]);
	db().query("create index reply_topicid on reply(topicid)");
	db().query("alter table forums add constraint forums_replyid foreign key(replyid) references reply(replyid) on delete set null");
	var msg = "您是第一次打开论坛，已成功为您初始化数据库，请刷新。";
	return sys.ismaster ? tojson({ msg: msg }) : errpage(msg, "系统初始化成功");
}
%>