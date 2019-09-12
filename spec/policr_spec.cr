require "./spec_helper"

alias Model = Policr::Model
alias Reason = Policr::ReportReason
alias ReportStatus = Policr::ReportStatus
alias UserRole = Policr::ReportUserRole
alias VoteType = Policr::VoteType
alias EnableStatus = Policr::EnableStatus
alias DeleteTarget = Policr::CleanDeleteTarget
alias SubfunctionType = Policr::SubfunctionType
alias ServiceMessage = Policr::ServiceMessage
alias ToggleTarget = Policr::ToggleTarget
alias QueUseFor = Policr::QueUseFor

macro def_models_alias(models)
  {% for model in models %}
    alias {{model}} = Model::{{model}}
  {% end %}
end

macro def_types_alias(types)
  {% for type in types %}
    alias {{type}} = Policr::{{type}}
  {% end %}
end

def_types_alias [VotingApplyParser]
def_models_alias [
  Question,
  Answer,
  Group,
  Admin,
]

describe Policr do
  it "arabic characters match" do
    arabic_characters = /^[\x{0600}-\x{06ff}-\x{0750}-\x{077f}-\x{08A0}-\x{08ff}-\x{fb50}-\x{fdff}-\x{fe70}-\x{feff} ]+$/
    r = "گچپژیلفقهمو" =~ arabic_characters
    false.should eq(r.is_a?(Nil))
  end

  it "arabic characters count" do
    arabic_characters = /[\x{0600}-\x{06ff}-\x{0750}-\x{077f}-\x{08A0}-\x{08ff}-\x{fb50}-\x{fdff}-\x{fe70}-\x{feff}]/
    i = 0
    "العَرَبِيَّة".gsub(arabic_characters) do |_|
      i += 1
    end
    12.should eq i
  end

  it "scan" do
    Policr.scan "."
  end

  it "parsers" do
    text =
      <<-TEXT
      -t 小红举报了小明对她的人身攻击言论，是否赞成？
      -d 赞成举报可能会让小明进入黑名单，反对会避免小明进入黑名单。
      -n 不应该赞成小红的举报，因为这是私人矛盾，应该交由群组内部解决。并且私人矛盾也不应该造成任何一方进入黑名单。
      - 赞成
      + 不赞成
      TEXT
    VotingApplyParser.parse!(text).should be_truthy
  end

  it "crud" do
    author_id = 340396281
    post_id = 18
    target_snapshot_id = 29
    target_user_id = 871769395
    target_msg_id = 234
    reason = Reason::MassAd.value
    status = ReportStatus::Begin.value
    role = UserRole::Creator.value
    from_chat_id = -1001301664514.to_i64

    r1 = Model::Report.create({
      author_id:          author_id.to_i32,
      post_id:            post_id,
      target_snapshot_id: target_snapshot_id,
      target_user_id:     target_user_id.to_i32,
      target_msg_id:      target_msg_id,
      reason:             reason,
      status:             status,
      role:               role,
      from_chat_id:       from_chat_id,
    })
    r1.should be_truthy

    v1 = r1.add_votes({:author_id => author_id.to_i64, :type => VoteType::Agree.value})
    v1.should be_truthy
    v2 = r1.add_votes({:author_id => author_id.to_i64, :type => VoteType::Abstention.value})
    v2.should be_truthy

    v_list = Model::Vote.all.where { _report_id == r1.id }.to_a
    v_list.size.should eq(2)
    v_list.each do |v|
      r = Model::Vote.delete(v.id)
      r.should be_truthy
      if r
        r.rows_affected.should eq(1)
      end
    end

    a1 = r1.add_appeals({:author_id => author_id, :done => true})
    a1.should be_truthy
    a2 = r1.add_appeals({:author_id => author_id, :done => false})
    a2.should be_truthy

    a_list = Model::Appeal.all.where { _report_id == r1.id }.to_a
    a_list.size.should eq(2)
    a_list.each do |a|
      r = Model::Appeal.delete(a.id)
      r.should be_truthy
      if r
        r.rows_affected.should eq(1)
      end
    end

    r = Model::Report.delete(r1.id)
    r.should be_truthy
    if r
      r.rows_affected.should eq(1)
    end

    # 干净模式
    cm1 = Model::CleanMode.create({
      chat_id:       from_chat_id,
      delete_target: DeleteTarget::TimeoutVerified.value,
      delay_sec:     nil,
      status:        EnableStatus::TurnOn.value,
    })
    cm1.should be_truthy
    r = Model::CleanMode.delete(cm1.id)
    r.should be_truthy
    if r
      r.rows_affected.should eq(1)
    end

    # 子功能
    sb1 = Model::Subfunction.create({
      chat_id: from_chat_id,
      type:    SubfunctionType::BanHalal.value,
      status:  EnableStatus::TurnOff.value,
    })

    is_disable = Model::Subfunction.disabled?(from_chat_id, SubfunctionType::UserJoin)
    is_disable.should eq(false)

    is_disable = Model::Subfunction.disabled?(from_chat_id, SubfunctionType::BanHalal)
    is_disable.should eq(true)

    sb1.should be_truthy
    r = Model::Subfunction.delete(sb1.id)
    r.should be_truthy
    if r
      r.rows_affected.should eq(1)
    end

    # 正确答案索引
    ti1 = Model::TrueIndex.create({
      chat_id: from_chat_id,
      msg_id:  target_msg_id,
      indices: [1, 2, 3, 4].join(","),
    })
    ti1.should be_truthy
    r = Model::TrueIndex.delete(ti1.id)
    r.should be_truthy
    if r
      r.rows_affected.should eq(1)
    end
    # 错误次数
    ec1 = Model::ErrorCount.create({
      chat_id: from_chat_id.to_i64,
      user_id: target_user_id.to_i64,
    })
    ec1.should be_truthy
    r = Model::ErrorCount.delete(ec1.id)
    r.should be_truthy
    if r
      r.rows_affected.should eq(1)
    end

    Model::ErrorCount.one_time from_chat_id, target_user_id
    1.should eq (Model::ErrorCount.counting(from_chat_id, target_user_id))
    Model::ErrorCount.destory from_chat_id, target_user_id
    0.should eq (Model::ErrorCount.counting(from_chat_id, target_user_id))

    ml = Model::MaxLength.create({
      chat_id: from_chat_id,
    })

    Model::MaxLength.update_total(from_chat_id, 999)
    Model::MaxLength.update_rows(from_chat_id, 99)
    total, rows = Model::MaxLength.values(from_chat_id)
    total.should be_truthy
    if total
      999.should eq(total)
    end
    rows.should be_truthy
    if total
      99.should eq(rows)
    end

    r = Model::MaxLength.delete(ml.id)
    r.should be_truthy
    if r
      r.rows_affected.should eq(1)
    end

    # 删除服务消息
    Model::AntiMessage.enable!(from_chat_id, ServiceMessage::JoinGroup)
    Model::AntiMessage.enabled?(from_chat_id, ServiceMessage::JoinGroup).should be_true
    Model::AntiMessage.disabled?(from_chat_id, ServiceMessage::LeaveGroup).should be_false
    Model::AntiMessage.disable!(from_chat_id, ServiceMessage::LeaveGroup)
    Model::AntiMessage.disabled?(from_chat_id, ServiceMessage::LeaveGroup).should be_true

    r = Model::AntiMessage.where { _chat_id == from_chat_id }.delete
    r.should be_truthy
    if r
      r.rows_affected.should eq(2)
    end

    # 格式限制
    Model::FormatLimit.put_list!(from_chat_id, ["mp4", "gif"])
    Model::FormatLimit.includes?(from_chat_id, "mp4").should be_true
    Model::FormatLimit.clear(from_chat_id)
    Model::FormatLimit.includes?(from_chat_id, "mp4").should be_false
    Model::FormatLimit.find(from_chat_id).should be_falsey

    # 模板
    Model::Template.enabled?(from_chat_id).should be_falsey
    t1 = Model::Template.set_content! from_chat_id, "我是模板内容"
    t1.should be_truthy
    Model::Template.enabled?(from_chat_id).should be_falsey
    Model::Template.enable from_chat_id
    Model::Template.enabled?(from_chat_id).should be_truthy
    Model::Template.disable from_chat_id
    Model::Template.enabled?(from_chat_id).should be_falsey
    Model::Template.delete(t1.id).should be_truthy

    # 开关
    Model::Toggle.enabled?(from_chat_id, ToggleTarget::SlientMode).should be_false
    Model::Toggle.disabled?(from_chat_id, ToggleTarget::SlientMode).should be_false
    t1 = Model::Toggle.enable! from_chat_id, ToggleTarget::SlientMode
    Model::Toggle.enabled?(from_chat_id, ToggleTarget::SlientMode).should be_true
    Model::Toggle.disabled?(from_chat_id, ToggleTarget::SlientMode).should be_false
    Model::Toggle.disable! from_chat_id, ToggleTarget::SlientMode
    Model::Toggle.enabled?(from_chat_id, ToggleTarget::SlientMode).should be_false
    Model::Toggle.disabled?(from_chat_id, ToggleTarget::SlientMode).should be_true
    Model::Toggle.delete(t1.id).should be_truthy

    # 问题/答案
    q1 = Question.create!({
      chat_id: from_chat_id,
      title:   "我是一个问题",
      desc:    "我是问题描述",
      note:    "我是答案注解",
      use_for: QueUseFor::VotingApplyQuiz.value,
      enabled: true,
    })
    q1.should be_truthy
    q2 = Question.create!({
      chat_id: from_chat_id,
      title:   "我是一个没启用的问题",
      desc:    "我是问题描述",
      note:    "我是答案注解",
      use_for: QueUseFor::VotingApplyQuiz.value,
      enabled: false,
    })
    q2.should be_truthy
    Question.all_voting_apply.size.should eq(2)
    Question.enabled_voting_apply.size.should eq(1)
    q1.add_answers({:name => "正确答案", :corrected => true})
    q1.add_answers({:name => "错误答案", :corrected => false})
    qq = Question.where {
      (_use_for == QueUseFor::VotingApplyQuiz.value) & (_enabled == true)
    }.first
    qq.should be_truthy
    if qq && (answers = qq.answers)
      answers = qq.answers
      answers.size.should eq(2)
      answers.each do |a|
        Answer.delete(a.id).should be_truthy
      end
    end
    Question.delete(q1.id).should be_truthy
    Question.delete(q2.id).should be_truthy

    # 群组
    g1 = Group.create!({chat_id: from_chat_id, title: "群组1"})
    g1.should be_truthy
    g1.add_admins({:user_id => author_id, :is_owner => false})
    # 管理员
    a1 = Admin.where { _user_id == author_id }.first
    a1.should be_truthy

    if g1 && a1
      Group.delete(g1.id).should be_truthy
      Admin.delete(a1.id).should be_truthy
    end
  end
end
