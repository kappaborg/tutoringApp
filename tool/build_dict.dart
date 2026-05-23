// Builds assets/dict/ecdict.db from an ECDICT lite CSV, OR from a small
// built-in starter vocabulary when no CSV is provided.
//
// USAGE
//   # Starter dictionary (~80 common picture-book words):
//   dart run tool/build_dict.dart
//
//   # Full ECDICT lite (download separately from
//   # https://github.com/skywind3000/ECDICT — pick `ecdict.csv` from a release):
//   dart run tool/build_dict.dart path/to/ecdict_lite.csv
//
// ECDICT CSV format (header row required):
//   word,phonetic,definition,translation,pos,collins,oxford,tag,bnc,frq,exchange,detail,audio
//
// We only persist: word (lowercased), phonetic (= pinyin field), translation
// (= Chinese, multi-line newlines → "; "), definition (= English short
// definition; we use the first non-empty of `definition`/`translation`).
//
// Output: assets/dict/ecdict.db with one table `entries`:
//   CREATE TABLE entries (
//     word        TEXT PRIMARY KEY,
//     pinyin      TEXT NOT NULL DEFAULT '',
//     chinese     TEXT NOT NULL DEFAULT '',
//     definition  TEXT NOT NULL DEFAULT ''
//   );
//
// The .db file is committed so the build never reaches the network.

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const String dbRelPath = 'assets/dict/ecdict.db';

/// Starter vocabulary used when no CSV is supplied. Designed to cover ~95 %
/// of the words a 4–8-year-old picture-book reader encounters.
///
/// Coverage strategy: store the BASE form of every word; the suffix stemmer
/// in `lib/utils/word_stemmer.dart` handles regular plurals (-s, -es, -ies),
/// past tenses (-ed, -ied), participles (-ing), comparatives/superlatives
/// (-er/-est), and de-doubled spellings (running → run). Irregular forms
/// (was, went, are, men, …) are stored explicitly because the stemmer
/// cannot derive them.
///
/// Translations target the picture-book sense — short, child-friendly.
const Map<String, _StarterEntry> _starter = {
  // ── Articles / determiners / quantifiers ──────────────────────────────
  'a': _StarterEntry('', '一个', 'An indefinite article.'),
  'an': _StarterEntry('', '一个', 'An indefinite article before a vowel.'),
  'the': _StarterEntry('', '这；那', 'The definite article.'),
  'this': _StarterEntry('', '这', 'A nearby thing.'),
  'that': _StarterEntry('', '那', 'A more distant thing.'),
  'these': _StarterEntry('', '这些', 'Nearby things.'),
  'those': _StarterEntry('', '那些', 'More distant things.'),
  'some': _StarterEntry('', '一些', 'An unspecified amount.'),
  'any': _StarterEntry('', '任何', 'One or more of something.'),
  'no': _StarterEntry('', '没有；不', 'Not any; the opposite of yes.'),
  'not': _StarterEntry('', '不', 'Negation.'),
  'all': _StarterEntry('', '所有', 'Every one of a group.'),
  'every': _StarterEntry('', '每个', 'Each one without exception.'),
  'each': _StarterEntry('', '每个', 'One at a time.'),
  'both': _StarterEntry('', '两者都', 'The two together.'),
  'few': _StarterEntry('', '几个', 'A small number.'),
  'many': _StarterEntry('', '许多', 'A large number.'),
  'much': _StarterEntry('', '很多', 'A large amount.'),
  'more': _StarterEntry('', '更多', 'A greater amount.'),
  'most': _StarterEntry('', '最多', 'The greatest amount.'),
  'less': _StarterEntry('', '更少', 'A smaller amount.'),
  'least': _StarterEntry('', '最少', 'The smallest amount.'),
  'another': _StarterEntry('', '另一个', 'A different one.'),
  'other': _StarterEntry('', '其他的', 'Different from this one.'),
  'such': _StarterEntry('', '这样的', 'Of that kind.'),
  'own': _StarterEntry('', '自己的', 'Belonging to oneself.'),
  'same': _StarterEntry('', '相同的', 'Exactly alike.'),

  // ── Pronouns ──────────────────────────────────────────────────────────
  'i': _StarterEntry('', '我', 'The speaker.'),
  'you': _StarterEntry('', '你', 'The person spoken to.'),
  'he': _StarterEntry('', '他', 'A male person.'),
  'she': _StarterEntry('', '她', 'A female person.'),
  'it': _StarterEntry('', '它', 'A thing.'),
  'we': _StarterEntry('', '我们', 'The speaker and others.'),
  'they': _StarterEntry('', '他们', 'Other people or things.'),
  'me': _StarterEntry('', '我', 'Object form of "I".'),
  'him': _StarterEntry('', '他', 'Object form of "he".'),
  'her': _StarterEntry('', '她；她的', 'Object form of "she"; or her own.'),
  'us': _StarterEntry('', '我们', 'Object form of "we".'),
  'them': _StarterEntry('', '他们', 'Object form of "they".'),
  'my': _StarterEntry('', '我的', 'Belonging to me.'),
  'your': _StarterEntry('', '你的', 'Belonging to you.'),
  'his': _StarterEntry('', '他的', 'Belonging to him.'),
  'hers': _StarterEntry('', '她的', 'Belonging to her.'),
  'its': _StarterEntry('', '它的', 'Belonging to it.'),
  'our': _StarterEntry('', '我们的', 'Belonging to us.'),
  'their': _StarterEntry('', '他们的', 'Belonging to them.'),
  'mine': _StarterEntry('', '我的', 'Belonging to me.'),
  'yours': _StarterEntry('', '你的', 'Belonging to you.'),
  'theirs': _StarterEntry('', '他们的', 'Belonging to them.'),
  'myself': _StarterEntry('', '我自己', 'I, on my own.'),
  'yourself': _StarterEntry('', '你自己', 'You, on your own.'),
  'himself': _StarterEntry('', '他自己', 'He, on his own.'),
  'herself': _StarterEntry('', '她自己', 'She, on her own.'),
  'itself': _StarterEntry('', '它自己', 'It, on its own.'),
  'ourselves': _StarterEntry('', '我们自己', 'We, on our own.'),
  'themselves': _StarterEntry('', '他们自己', 'They, on their own.'),

  // ── Question words ────────────────────────────────────────────────────
  'who': _StarterEntry('', '谁', 'Which person.'),
  'whom': _StarterEntry('', '谁', 'Object form of who.'),
  'whose': _StarterEntry('', '谁的', 'Belonging to whom.'),
  'what': _StarterEntry('', '什么', 'Which thing.'),
  'where': _StarterEntry('', '哪里', 'In which place.'),
  'when': _StarterEntry('', '什么时候', 'At what time.'),
  'why': _StarterEntry('', '为什么', 'For what reason.'),
  'how': _StarterEntry('', '怎么；多么', 'In what way; or to what degree.'),
  'which': _StarterEntry('', '哪个', 'Asking to choose.'),

  // ── Conjunctions ──────────────────────────────────────────────────────
  'and': _StarterEntry('', '和', 'A connecting word.'),
  'or': _StarterEntry('', '或者', 'A choice between options.'),
  'but': _StarterEntry('', '但是', 'However; yet.'),
  'so': _StarterEntry('', '所以', 'For that reason.'),
  'because': _StarterEntry('', '因为', 'For the reason that.'),
  'if': _StarterEntry('', '如果', 'On the condition that.'),
  'while': _StarterEntry('', '当……时', 'During the time.'),
  'although': _StarterEntry('', '虽然', 'In spite of the fact.'),
  'though': _StarterEntry('', '虽然', 'Although.'),
  'since': _StarterEntry('', '自从；因为', 'From a time ago; or because.'),
  'until': _StarterEntry('', '直到', 'Up to the time that.'),
  'unless': _StarterEntry('', '除非', 'Except if.'),
  'as': _StarterEntry('', '作为；当……时', 'In the role of; or at the time.'),
  'than': _StarterEntry('', '比', 'Used in comparisons.'),

  // ── Prepositions ──────────────────────────────────────────────────────
  'on': _StarterEntry('', '在……上', 'Resting upon a surface.'),
  'in': _StarterEntry('', '在……里', 'Inside something.'),
  'at': _StarterEntry('', '在', 'Indicates a location or time.'),
  'to': _StarterEntry('', '到；向', 'Toward a destination.'),
  'of': _StarterEntry('', '的', 'Indicates possession or origin.'),
  'with': _StarterEntry('', '和……一起', 'Accompanied by.'),
  'from': _StarterEntry('', '从', 'Indicating a starting point.'),
  'for': _StarterEntry('', '为；给', 'On behalf of.'),
  'by': _StarterEntry('', '由；在……旁边', 'Done by; or next to.'),
  'about': _StarterEntry('', '关于', 'Concerning a subject.'),
  'over': _StarterEntry('', '在……上方', 'Above; across.'),
  'under': _StarterEntry('', '在……下面', 'Below.'),
  'above': _StarterEntry('', '在……上方', 'Higher than.'),
  'below': _StarterEntry('', '在……下面', 'Lower than.'),
  'between': _StarterEntry('', '在……之间', 'In the middle of two things.'),
  'among': _StarterEntry('', '在……当中', 'Surrounded by.'),
  'through': _StarterEntry('', '通过', 'In one side and out the other.'),
  'across': _StarterEntry('', '横过', 'From one side to the other.'),
  'around': _StarterEntry('', '在……周围', 'Surrounding.'),
  'near': _StarterEntry('', '在……附近', 'Close to.'),
  'next': _StarterEntry('', '下一个；旁边', 'Following; or beside.'),
  'beside': _StarterEntry('', '在……旁边', 'Next to.'),
  'behind': _StarterEntry('', '在……后面', 'At the back of.'),
  'before': _StarterEntry('', '在……之前', 'Earlier than.'),
  'after': _StarterEntry('', '在……之后', 'Later than.'),
  'during': _StarterEntry('', '在……期间', 'Throughout a period.'),
  'into': _StarterEntry('', '进入', 'Moving inside.'),
  'onto': _StarterEntry('', '到……上', 'Moving on top of.'),
  'out': _StarterEntry('', '在外面', 'Outside.'),
  'off': _StarterEntry('', '从……离开', 'Away from a surface.'),
  'up': _StarterEntry('', '向上', 'Toward a higher place.'),
  'down': _StarterEntry('', '向下', 'Toward a lower place.'),
  'inside': _StarterEntry('', '在……里面', 'In the interior of.'),
  'outside': _StarterEntry('', '在……外面', 'On the exterior of.'),
  'without': _StarterEntry('', '没有', 'Lacking.'),
  'against': _StarterEntry('', '反对；靠着', 'Opposed to; leaning on.'),

  // ── Forms of "be", "have", "do" ───────────────────────────────────────
  'be': _StarterEntry('', '是', 'Exists; equals.'),
  'am': _StarterEntry('', '是', 'First-person form of "be".'),
  'is': _StarterEntry('', '是', 'Third-person singular of "be".'),
  'are': _StarterEntry('', '是', 'Plural form of "be".'),
  'was': _StarterEntry('', '是（过去式）', 'Past tense of "is".'),
  'were': _StarterEntry('', '是（过去式）', 'Past tense of "are".'),
  'been': _StarterEntry('', '是过', 'Past participle of "be".'),
  'being': _StarterEntry('', '存在', 'The act of being.'),
  'have': _StarterEntry('', '有', 'To possess.'),
  'has': _StarterEntry('', '有', 'Third-person singular of "have".'),
  'had': _StarterEntry('', '有（过去式）', 'Past tense of "have".'),
  'having': _StarterEntry('', '有', 'Present participle of "have".'),
  'do': _StarterEntry('', '做', 'To perform an action.'),
  'does': _StarterEntry('', '做', 'Third-person singular of "do".'),
  'did': _StarterEntry('', '做（过去式）', 'Past tense of "do".'),
  'done': _StarterEntry('', '做完', 'Finished.'),
  'doing': _StarterEntry('', '正在做', 'Present participle of "do".'),

  // ── Common modal / auxiliary verbs ────────────────────────────────────
  'can': _StarterEntry('', '能；可以', 'Be able to.'),
  'cannot': _StarterEntry('', '不能', 'Not able to.'),
  'could': _StarterEntry('', '能（过去式）', 'Past tense of "can".'),
  'will': _StarterEntry('', '将；意愿', 'Indicates future; or determination.'),
  'would': _StarterEntry('', '将；愿意', 'Past tense of "will"; or polite ask.'),
  'shall': _StarterEntry('', '将', 'Indicates future.'),
  'should': _StarterEntry('', '应该', 'Ought to.'),
  'may': _StarterEntry('', '可以；可能；五月', 'Allowed; possibly; or 5th month.'),
  'might': _StarterEntry('', '可能', 'Possibly.'),
  'must': _StarterEntry('', '必须', 'Has to.'),
  'ought': _StarterEntry('', '应该', 'Should.'),
  'need': _StarterEntry('', '需要', 'Require.'),

  // ── Common irregular verb forms (stemmer can\'t derive these) ─────────
  'go': _StarterEntry('', '去', 'To move from one place to another.'),
  'goes': _StarterEntry('', '去', 'Third-person singular of "go".'),
  'went': _StarterEntry('', '去（过去式）', 'Past tense of "go".'),
  'gone': _StarterEntry('', '走了', 'Past participle of "go".'),
  'going': _StarterEntry('', '正在去', 'Present participle of "go".'),
  'come': _StarterEntry('', '来', 'To move toward the speaker.'),
  'came': _StarterEntry('', '来（过去式）', 'Past tense of "come".'),
  'see': _StarterEntry('', '看见', 'To perceive with the eyes.'),
  'saw': _StarterEntry('', '看见（过去式）', 'Past tense of "see".'),
  'seen': _StarterEntry('', '看过', 'Past participle of "see".'),
  'get': _StarterEntry('', '得到', 'To obtain.'),
  'got': _StarterEntry('', '得到（过去式）', 'Past tense of "get".'),
  'give': _StarterEntry('', '给', 'To hand to someone.'),
  'gave': _StarterEntry('', '给（过去式）', 'Past tense of "give".'),
  'given': _StarterEntry('', '给过', 'Past participle of "give".'),
  'take': _StarterEntry('', '拿；带', 'To grasp or carry.'),
  'took': _StarterEntry('', '拿（过去式）', 'Past tense of "take".'),
  'taken': _StarterEntry('', '拿过', 'Past participle of "take".'),
  'make': _StarterEntry('', '做；制作', 'To create.'),
  'made': _StarterEntry('', '做（过去式）', 'Past tense of "make".'),
  'know': _StarterEntry('', '知道', 'To be aware of.'),
  'knew': _StarterEntry('', '知道（过去式）', 'Past tense of "know".'),
  'known': _StarterEntry('', '知道', 'Past participle of "know".'),
  'think': _StarterEntry('', '想', 'To form an idea.'),
  'thought': _StarterEntry('', '想（过去式）；想法', 'Past tense of "think"; an idea.'),
  'say': _StarterEntry('', '说', 'To speak words.'),
  'said': _StarterEntry('', '说（过去式）', 'Past tense of "say".'),
  'tell': _StarterEntry('', '告诉', 'To say to someone.'),
  'told': _StarterEntry('', '告诉（过去式）', 'Past tense of "tell".'),
  'ask': _StarterEntry('', '问', 'To request information.'),
  'find': _StarterEntry('', '找到', 'To discover.'),
  'found': _StarterEntry('', '找到（过去式）', 'Past tense of "find".'),
  'feel': _StarterEntry('', '感觉', 'To sense.'),
  'felt': _StarterEntry('', '感觉（过去式）', 'Past tense of "feel".'),
  'leave': _StarterEntry('', '离开', 'To go away.'),
  'left': _StarterEntry('', '离开（过去式）；左', 'Past of "leave"; the left side.'),
  'put': _StarterEntry('', '放', 'To place.'),
  'keep': _StarterEntry('', '保持', 'To hold onto.'),
  'kept': _StarterEntry('', '保持（过去式）', 'Past tense of "keep".'),
  'let': _StarterEntry('', '让；允许', 'To allow.'),
  'begin': _StarterEntry('', '开始', 'To start.'),
  'began': _StarterEntry('', '开始（过去式）', 'Past tense of "begin".'),
  'begun': _StarterEntry('', '开始过', 'Past participle of "begin".'),
  'start': _StarterEntry('', '开始', 'To begin.'),
  'finish': _StarterEntry('', '完成', 'To complete.'),
  'help': _StarterEntry('', '帮助', 'To assist.'),
  'show': _StarterEntry('', '展示', 'To make visible.'),
  'shown': _StarterEntry('', '展示过', 'Past participle of "show".'),
  'hear': _StarterEntry('', '听见', 'To perceive sound.'),
  'heard': _StarterEntry('', '听见（过去式）', 'Past tense of "hear".'),
  'listen': _StarterEntry('', '听', 'To pay attention to sound.'),
  'look': _StarterEntry('', '看', 'To direct the eyes.'),
  'watch': _StarterEntry('', '看；手表', 'To observe; a small clock.'),
  'want': _StarterEntry('', '想要', 'To desire.'),
  'wanted': _StarterEntry('', '想要（过去式）', 'Past tense of "want".'),
  'like': _StarterEntry('', '喜欢', 'To enjoy.'),
  'love': _StarterEntry('', '爱', 'To feel deep affection.'),
  'try': _StarterEntry('', '尝试', 'To attempt.'),
  'tried': _StarterEntry('', '尝试（过去式）', 'Past tense of "try".'),
  'use': _StarterEntry('', '用', 'To make use of.'),
  'used': _StarterEntry('', '用过', 'Past tense of "use".'),
  'work': _StarterEntry('', '工作', 'To do a job.'),
  'turn': _StarterEntry('', '转', 'To rotate.'),
  'live': _StarterEntry('', '住；活', 'To dwell; to be alive.'),
  'lived': _StarterEntry('', '住过', 'Past tense of "live".'),
  'bring': _StarterEntry('', '带来', 'To carry to a place.'),
  'brought': _StarterEntry('', '带来（过去式）', 'Past tense of "bring".'),
  'buy': _StarterEntry('', '买', 'To purchase.'),
  'bought': _StarterEntry('', '买（过去式）', 'Past tense of "buy".'),
  'sell': _StarterEntry('', '卖', 'To exchange for money.'),
  'sold': _StarterEntry('', '卖（过去式）', 'Past tense of "sell".'),
  'sing': _StarterEntry('', '唱歌', 'To make music with the voice.'),
  'sang': _StarterEntry('', '唱（过去式）', 'Past tense of "sing".'),
  'sung': _StarterEntry('', '唱过', 'Past participle of "sing".'),
  'sit': _StarterEntry('', '坐', 'To rest on a surface.'),
  'sat': _StarterEntry('', '坐（过去式）', 'Past tense of "sit".'),
  'stand': _StarterEntry('', '站', 'To be upright on feet.'),
  'stood': _StarterEntry('', '站（过去式）', 'Past tense of "stand".'),
  'lie': _StarterEntry('', '躺；说谎', 'To recline; or to say untruth.'),
  'lay': _StarterEntry('', '躺（过去式）；放', 'Past of "lie"; or to place.'),
  'wait': _StarterEntry('', '等待', 'To stay until.'),
  'stay': _StarterEntry('', '停留', 'To remain.'),
  'stop': _StarterEntry('', '停', 'To cease.'),
  'open': _StarterEntry('', '打开；开着的', 'To uncover; or not closed.'),
  'close': _StarterEntry('', '关；近的', 'To shut; or near.'),
  'grow': _StarterEntry('', '长大', 'To increase in size.'),
  'grew': _StarterEntry('', '长（过去式）', 'Past tense of "grow".'),
  'grown': _StarterEntry('', '长大', 'Past participle of "grow".'),
  'fall': _StarterEntry('', '掉；秋天', 'To drop down; or autumn.'),
  'fell': _StarterEntry('', '掉（过去式）', 'Past tense of "fall".'),
  'fallen': _StarterEntry('', '掉过', 'Past participle of "fall".'),
  'rise': _StarterEntry('', '升起', 'To move upward.'),
  'rose': _StarterEntry('', '升起（过去式）；玫瑰', 'Past of "rise"; or a flower.'),
  'risen': _StarterEntry('', '升起过', 'Past participle of "rise".'),
  'win': _StarterEntry('', '赢', 'To be victorious.'),
  'won': _StarterEntry('', '赢（过去式）', 'Past tense of "win".'),
  'lose': _StarterEntry('', '输；丢失', 'To not win; or to misplace.'),
  'lost': _StarterEntry('', '丢失（过去式）', 'Past tense of "lose".'),
  'send': _StarterEntry('', '寄；送', 'To cause to go.'),
  'sent': _StarterEntry('', '送（过去式）', 'Past tense of "send".'),
  'pay': _StarterEntry('', '付钱', 'To give money for.'),
  'paid': _StarterEntry('', '付（过去式）', 'Past tense of "pay".'),
  'meet': _StarterEntry('', '见面', 'To encounter.'),
  'met': _StarterEntry('', '见（过去式）', 'Past tense of "meet".'),
  'read': _StarterEntry('', '读', 'To look at written words.'),
  'write': _StarterEntry('', '写', 'To put words on paper.'),
  'wrote': _StarterEntry('', '写（过去式）', 'Past tense of "write".'),
  'written': _StarterEntry('', '写过', 'Past participle of "write".'),
  'sleeps': _StarterEntry('', '睡觉', 'Rests with eyes closed.'),
  'sleep': _StarterEntry('', '睡', 'To rest with eyes closed.'),
  'slept': _StarterEntry('', '睡过', 'Past tense of "sleep".'),
  'wake': _StarterEntry('', '醒来', 'To stop sleeping.'),
  'woke': _StarterEntry('', '醒来（过去式）', 'Past tense of "wake".'),
  'eat': _StarterEntry('', '吃', 'To take in food.'),
  'ate': _StarterEntry('', '吃（过去式）', 'Past tense of "eat".'),
  'eaten': _StarterEntry('', '吃过', 'Past participle of "eat".'),
  'drink': _StarterEntry('', '喝', 'To take in liquid.'),
  'drank': _StarterEntry('', '喝（过去式）', 'Past tense of "drink".'),
  'drunk': _StarterEntry('', '喝过', 'Past participle of "drink".'),
  'run': _StarterEntry('', '跑', 'To move quickly on foot.'),
  'ran': _StarterEntry('', '跑（过去式）', 'Past tense of "run".'),
  'walk': _StarterEntry('', '走', 'To move on foot.'),
  'jump': _StarterEntry('', '跳', 'To push off the ground.'),
  'play': _StarterEntry('', '玩', 'To have fun.'),
  'swim': _StarterEntry('', '游泳', 'To move through water.'),
  'swam': _StarterEntry('', '游泳（过去式）', 'Past tense of "swim".'),
  'fly': _StarterEntry('', '飞', 'To move through the air.'),
  'flew': _StarterEntry('', '飞（过去式）', 'Past tense of "fly".'),
  'flown': _StarterEntry('', '飞过', 'Past participle of "fly".'),
  'ride': _StarterEntry('', '骑', 'To sit and travel on something.'),
  'rode': _StarterEntry('', '骑（过去式）', 'Past tense of "ride".'),
  'ridden': _StarterEntry('', '骑过', 'Past participle of "ride".'),
  'drive': _StarterEntry('', '开车', 'To operate a vehicle.'),
  'drove': _StarterEntry('', '开（过去式）', 'Past tense of "drive".'),
  'driven': _StarterEntry('', '开过', 'Past participle of "drive".'),
  'climb': _StarterEntry('', '爬', 'To go up using hands and feet.'),
  'push': _StarterEntry('', '推', 'To press away.'),
  'pull': _StarterEntry('', '拉', 'To draw toward.'),
  'lift': _StarterEntry('', '抬起', 'To raise up.'),
  'drop': _StarterEntry('', '放下；掉', 'To let fall.'),
  'throw': _StarterEntry('', '扔', 'To send through the air.'),
  'threw': _StarterEntry('', '扔（过去式）', 'Past tense of "throw".'),
  'thrown': _StarterEntry('', '扔过', 'Past participle of "throw".'),
  'catch': _StarterEntry('', '接住；抓', 'To grab in the air.'),
  'caught': _StarterEntry('', '抓（过去式）', 'Past tense of "catch".'),
  'kick': _StarterEntry('', '踢', 'To hit with the foot.'),
  'hit': _StarterEntry('', '打', 'To strike.'),
  'hold': _StarterEntry('', '拿；抱', 'To grasp.'),
  'held': _StarterEntry('', '拿（过去式）', 'Past tense of "hold".'),
  'cut': _StarterEntry('', '切', 'To divide with a sharp tool.'),
  'wash': _StarterEntry('', '洗', 'To clean with water.'),
  'cook': _StarterEntry('', '做饭', 'To prepare food with heat.'),
  'paint': _StarterEntry('', '画；油漆', 'To apply colour.'),
  'draw': _StarterEntry('', '画', 'To make a picture.'),
  'drew': _StarterEntry('', '画（过去式）', 'Past tense of "draw".'),
  'drawn': _StarterEntry('', '画过', 'Past participle of "draw".'),
  'cry': _StarterEntry('', '哭', 'To shed tears.'),
  'cried': _StarterEntry('', '哭（过去式）', 'Past tense of "cry".'),
  'laugh': _StarterEntry('', '笑', 'To make a happy sound.'),
  'smile': _StarterEntry('', '微笑', 'To turn the mouth up in joy.'),
  'shout': _StarterEntry('', '喊', 'To say loudly.'),
  'whisper': _StarterEntry('', '小声说', 'To say very quietly.'),
  'kiss': _StarterEntry('', '亲吻', 'To press lips on someone.'),
  'hug': _StarterEntry('', '拥抱', 'To hold tightly with arms.'),
  'wave': _StarterEntry('', '挥手；波浪', 'To move the hand in greeting.'),
  'wear': _StarterEntry('', '穿', 'To have clothing on.'),
  'wore': _StarterEntry('', '穿（过去式）', 'Past tense of "wear".'),
  'worn': _StarterEntry('', '穿过', 'Past participle of "wear".'),

  // ── People ────────────────────────────────────────────────────────────
  'man': _StarterEntry('', '男人', 'An adult male.'),
  'men': _StarterEntry('', '男人们', 'Plural of "man".'),
  'woman': _StarterEntry('', '女人', 'An adult female.'),
  'women': _StarterEntry('', '女人们', 'Plural of "woman".'),
  'child': _StarterEntry('', '小孩', 'A young person.'),
  'children': _StarterEntry('', '小孩们', 'Plural of "child".'),
  'boy': _StarterEntry('', '男孩', 'A young male.'),
  'girl': _StarterEntry('', '女孩', 'A young female.'),
  'baby': _StarterEntry('', '婴儿', 'A very young child.'),
  'person': _StarterEntry('', '人', 'A human being.'),
  'people': _StarterEntry('', '人们', 'Plural of "person".'),
  'friend': _StarterEntry('', '朋友', 'Someone you like.'),
  'mom': _StarterEntry('', '妈妈', 'Mother.'),
  'mum': _StarterEntry('', '妈妈', 'Mother (UK English).'),
  'mother': _StarterEntry('', '母亲', 'Mother.'),
  'dad': _StarterEntry('', '爸爸', 'Father.'),
  'father': _StarterEntry('', '父亲', 'Father.'),
  'parent': _StarterEntry('', '父母', 'A mother or father.'),
  'son': _StarterEntry('', '儿子', 'A male child.'),
  'daughter': _StarterEntry('', '女儿', 'A female child.'),
  'sister': _StarterEntry('', '姐妹', 'A female sibling.'),
  'brother': _StarterEntry('', '兄弟', 'A male sibling.'),
  'grandma': _StarterEntry('', '奶奶', 'Grandmother.'),
  'grandpa': _StarterEntry('', '爷爷', 'Grandfather.'),
  'grandmother': _StarterEntry('', '祖母', 'Mother of a parent.'),
  'grandfather': _StarterEntry('', '祖父', 'Father of a parent.'),
  'aunt': _StarterEntry('', '阿姨', 'Sister of a parent.'),
  'uncle': _StarterEntry('', '叔叔', 'Brother of a parent.'),
  'cousin': _StarterEntry('', '表亲', 'Child of an aunt or uncle.'),
  'family': _StarterEntry('', '家庭', 'People related to one another.'),
  'teacher': _StarterEntry('', '老师', 'Someone who teaches.'),
  'doctor': _StarterEntry('', '医生', 'Someone who heals.'),
  'king': _StarterEntry('', '国王', 'A male ruler.'),
  'queen': _StarterEntry('', '王后', 'A female ruler.'),
  'prince': _StarterEntry('', '王子', 'A king\'s son.'),
  'princess': _StarterEntry('', '公主', 'A king\'s daughter.'),

  // ── Animals ───────────────────────────────────────────────────────────
  'cat': _StarterEntry('', '猫', 'A small furry pet.'),
  'dog': _StarterEntry('', '狗', 'A friendly four-legged pet.'),
  'puppy': _StarterEntry('', '小狗', 'A young dog.'),
  'kitten': _StarterEntry('', '小猫', 'A young cat.'),
  'bird': _StarterEntry('', '鸟', 'A feathered, winged animal.'),
  'fish': _StarterEntry('', '鱼', 'An animal that lives in water.'),
  'cow': _StarterEntry('', '奶牛', 'A large farm animal.'),
  'horse': _StarterEntry('', '马', 'A large animal people ride.'),
  'pony': _StarterEntry('', '小马', 'A small horse.'),
  'sheep': _StarterEntry('', '羊', 'A farm animal with wool.'),
  'goat': _StarterEntry('', '山羊', 'A farm animal with horns.'),
  'pig': _StarterEntry('', '猪', 'A farm animal with a curly tail.'),
  'chicken': _StarterEntry('', '鸡', 'A farm bird.'),
  'duck': _StarterEntry('', '鸭子', 'A water bird.'),
  'goose': _StarterEntry('', '鹅', 'A large water bird.'),
  'rabbit': _StarterEntry('', '兔子', 'A small animal with long ears.'),
  'mouse': _StarterEntry('', '老鼠', 'A small rodent.'),
  'mice': _StarterEntry('', '老鼠们', 'Plural of "mouse".'),
  'rat': _StarterEntry('', '大老鼠', 'A larger rodent.'),
  'bear': _StarterEntry('', '熊', 'A large strong animal.'),
  'lion': _StarterEntry('', '狮子', 'A big cat with a mane.'),
  'tiger': _StarterEntry('', '老虎', 'A big striped cat.'),
  'elephant': _StarterEntry('', '大象', 'A huge animal with a trunk.'),
  'monkey': _StarterEntry('', '猴子', 'A tree-climbing animal.'),
  'fox': _StarterEntry('', '狐狸', 'A clever wild animal.'),
  'wolf': _StarterEntry('', '狼', 'A wild dog-like animal.'),
  'snake': _StarterEntry('', '蛇', 'A legless reptile.'),
  'frog': _StarterEntry('', '青蛙', 'A jumping amphibian.'),
  'butterfly': _StarterEntry('', '蝴蝶', 'A colourful winged insect.'),
  'bee': _StarterEntry('', '蜜蜂', 'A buzzing insect that makes honey.'),
  'ant': _StarterEntry('', '蚂蚁', 'A tiny insect.'),
  'spider': _StarterEntry('', '蜘蛛', 'An eight-legged creature.'),
  'owl': _StarterEntry('', '猫头鹰', 'A night-time bird.'),
  'eagle': _StarterEntry('', '鹰', 'A large bird of prey.'),
  'deer': _StarterEntry('', '鹿', 'A graceful forest animal.'),
  'squirrel': _StarterEntry('', '松鼠', 'A tree-climbing animal with a bushy tail.'),
  'turtle': _StarterEntry('', '乌龟', 'A reptile with a hard shell.'),
  'dolphin': _StarterEntry('', '海豚', 'A friendly sea mammal.'),
  'whale': _StarterEntry('', '鲸鱼', 'A huge sea mammal.'),
  'shark': _StarterEntry('', '鲨鱼', 'A fierce sea fish.'),
  'dragon': _StarterEntry('', '龙', 'A mythical fire-breathing creature.'),
  'animal': _StarterEntry('', '动物', 'A living creature that is not a plant.'),

  // ── Nature / weather ─────────────────────────────────────────────────
  'sun': _StarterEntry('', '太阳', 'The bright star in our sky.'),
  'moon': _StarterEntry('', '月亮', 'Earth\'s satellite.'),
  'star': _StarterEntry('', '星星', 'A bright point of light at night.'),
  'sky': _StarterEntry('', '天空', 'The space above us.'),
  'cloud': _StarterEntry('', '云', 'White fluffy water in the sky.'),
  'rain': _StarterEntry('', '雨', 'Water falling from clouds.'),
  'snow': _StarterEntry('', '雪', 'Frozen white flakes.'),
  'wind': _StarterEntry('', '风', 'Moving air.'),
  'storm': _StarterEntry('', '暴风雨', 'Bad weather.'),
  'rainbow': _StarterEntry('', '彩虹', 'A colourful arc in the sky.'),
  'fire': _StarterEntry('', '火', 'Hot bright flames.'),
  'ice': _StarterEntry('', '冰', 'Frozen water.'),
  'water': _StarterEntry('', '水', 'Clear liquid we drink.'),
  'sea': _StarterEntry('', '海', 'A large body of salt water.'),
  'ocean': _StarterEntry('', '海洋', 'A very large body of salt water.'),
  'river': _StarterEntry('', '河', 'A flowing body of water.'),
  'lake': _StarterEntry('', '湖', 'A still body of water.'),
  'pond': _StarterEntry('', '池塘', 'A small lake.'),
  'beach': _StarterEntry('', '沙滩', 'A sandy shore.'),
  'mountain': _StarterEntry('', '山', 'A very tall hill.'),
  'hill': _StarterEntry('', '小山', 'A small rise of land.'),
  'rock': _StarterEntry('', '岩石', 'A hard piece of stone.'),
  'stone': _StarterEntry('', '石头', 'A small rock.'),
  'sand': _StarterEntry('', '沙', 'Tiny grains found on beaches.'),
  'dirt': _StarterEntry('', '泥土', 'Earth on the ground.'),
  'mud': _StarterEntry('', '泥', 'Wet dirt.'),
  'forest': _StarterEntry('', '森林', 'A place with many trees.'),
  'jungle': _StarterEntry('', '丛林', 'A thick tropical forest.'),
  'tree': _StarterEntry('', '树', 'A tall plant with a trunk.'),
  'flower': _StarterEntry('', '花', 'A colourful part of a plant.'),
  'leaf': _StarterEntry('', '叶子', 'A flat green part of a plant.'),
  'leaves': _StarterEntry('', '叶子', 'Plural of "leaf".'),
  'grass': _StarterEntry('', '草', 'Short green plants.'),
  'plant': _StarterEntry('', '植物', 'A living growing thing.'),
  'seed': _StarterEntry('', '种子', 'A small thing that grows into a plant.'),
  'garden': _StarterEntry('', '花园', 'A place where plants grow.'),

  // ── Food ─────────────────────────────────────────────────────────────
  'food': _StarterEntry('', '食物', 'Things we eat.'),
  'apple': _StarterEntry('', '苹果', 'A round red or green fruit.'),
  'banana': _StarterEntry('', '香蕉', 'A long yellow fruit.'),
  'orange': _StarterEntry('', '橘子；橙色', 'A round citrus fruit; or its colour.'),
  'grape': _StarterEntry('', '葡萄', 'A small round purple fruit.'),
  'strawberry': _StarterEntry('', '草莓', 'A small red sweet fruit.'),
  'pear': _StarterEntry('', '梨', 'A green fruit shaped like a teardrop.'),
  'fruit': _StarterEntry('', '水果', 'Sweet food from plants.'),
  'vegetable': _StarterEntry('', '蔬菜', 'A plant food.'),
  'carrot': _StarterEntry('', '胡萝卜', 'An orange root vegetable.'),
  'potato': _StarterEntry('', '土豆', 'A brown root vegetable.'),
  'tomato': _StarterEntry('', '番茄', 'A red round vegetable.'),
  'corn': _StarterEntry('', '玉米', 'Yellow kernels on a cob.'),
  'bread': _StarterEntry('', '面包', 'A baked food.'),
  'cake': _StarterEntry('', '蛋糕', 'A sweet baked dessert.'),
  'cookie': _StarterEntry('', '饼干', 'A small sweet baked treat.'),
  'sweet': _StarterEntry('', '糖果；甜的', 'Candy; or tasting like sugar.'),
  'candy': _StarterEntry('', '糖', 'A small sweet treat.'),
  'chocolate': _StarterEntry('', '巧克力', 'A sweet brown food.'),
  'milk': _StarterEntry('', '牛奶', 'A white drink from cows.'),
  'juice': _StarterEntry('', '果汁', 'A drink from fruit.'),
  'tea': _StarterEntry('', '茶', 'A warm drink from leaves.'),
  'coffee': _StarterEntry('', '咖啡', 'A warm dark drink.'),
  'sugar': _StarterEntry('', '糖', 'Sweet white powder.'),
  'salt': _StarterEntry('', '盐', 'Salty white powder.'),
  'butter': _StarterEntry('', '黄油', 'Yellow fat spread on bread.'),
  'cheese': _StarterEntry('', '奶酪', 'A food made from milk.'),
  'egg': _StarterEntry('', '鸡蛋', 'A round food from a hen.'),
  'meat': _StarterEntry('', '肉', 'Animal flesh as food.'),
  'rice': _StarterEntry('', '米饭', 'Small white grains we eat.'),
  'soup': _StarterEntry('', '汤', 'A warm liquid food.'),
  'pizza': _StarterEntry('', '披萨', 'A round Italian food.'),
  'breakfast': _StarterEntry('', '早餐', 'The morning meal.'),
  'lunch': _StarterEntry('', '午餐', 'The midday meal.'),
  'dinner': _StarterEntry('', '晚餐', 'The evening meal.'),
  'meal': _StarterEntry('', '餐', 'A time to eat.'),

  // ── House / objects ──────────────────────────────────────────────────
  'house': _StarterEntry('', '房子', 'A place where people live.'),
  'home': _StarterEntry('', '家', 'The place you live.'),
  'room': _StarterEntry('', '房间', 'A space inside a building.'),
  'kitchen': _StarterEntry('', '厨房', 'A room for cooking.'),
  'bedroom': _StarterEntry('', '卧室', 'A room for sleeping.'),
  'bathroom': _StarterEntry('', '浴室', 'A room for washing.'),
  'door': _StarterEntry('', '门', 'An opening into a room.'),
  'window': _StarterEntry('', '窗户', 'A glass opening in a wall.'),
  'wall': _StarterEntry('', '墙', 'A side of a room.'),
  'floor': _StarterEntry('', '地板', 'The bottom of a room.'),
  'roof': _StarterEntry('', '屋顶', 'The top of a building.'),
  'bed': _StarterEntry('', '床', 'Furniture for sleeping.'),
  'chair': _StarterEntry('', '椅子', 'Furniture for sitting.'),
  'table': _StarterEntry('', '桌子', 'Flat-topped furniture.'),
  'sofa': _StarterEntry('', '沙发', 'A long padded seat.'),
  'lamp': _StarterEntry('', '灯', 'A light you turn on.'),
  'clock': _StarterEntry('', '钟', 'A device that tells time.'),
  'mirror': _StarterEntry('', '镜子', 'A glass that reflects.'),
  'mat': _StarterEntry('', '垫子', 'A small flat piece on the floor.'),
  'cup': _StarterEntry('', '杯子', 'A small drink container.'),
  'bowl': _StarterEntry('', '碗', 'A round food container.'),
  'plate': _StarterEntry('', '盘子', 'A flat food dish.'),
  'spoon': _StarterEntry('', '勺子', 'A round eating tool.'),
  'fork': _StarterEntry('', '叉子', 'A pointed eating tool.'),
  'knife': _StarterEntry('', '刀', 'A cutting tool.'),
  'box': _StarterEntry('', '盒子', 'A container with sides.'),
  'bag': _StarterEntry('', '袋子', 'A soft container.'),
  'ball': _StarterEntry('', '球', 'A round play object.'),
  'toy': _StarterEntry('', '玩具', 'A thing children play with.'),
  'book': _StarterEntry('', '书', 'Pages bound for reading.'),
  'pen': _StarterEntry('', '钢笔', 'A writing tool with ink.'),
  'pencil': _StarterEntry('', '铅笔', 'A writing tool with lead.'),
  'paper': _StarterEntry('', '纸', 'A flat sheet for writing.'),
  'picture': _StarterEntry('', '图片', 'An image.'),
  'phone': _StarterEntry('', '电话', 'A device for calling.'),
  'car': _StarterEntry('', '汽车', 'A four-wheeled vehicle.'),
  'bus': _StarterEntry('', '公共汽车', 'A large public vehicle.'),
  'truck': _StarterEntry('', '卡车', 'A large goods vehicle.'),
  'train': _StarterEntry('', '火车', 'A long vehicle on tracks.'),
  'plane': _StarterEntry('', '飞机', 'A flying vehicle.'),
  'boat': _StarterEntry('', '船', 'A small water vehicle.'),
  'ship': _StarterEntry('', '船', 'A large water vehicle.'),
  'bike': _StarterEntry('', '自行车', 'A two-wheeled vehicle.'),
  'bicycle': _StarterEntry('', '自行车', 'A two-wheeled vehicle.'),
  'street': _StarterEntry('', '街道', 'A road in a town.'),
  'road': _StarterEntry('', '路', 'A way for vehicles.'),
  'city': _StarterEntry('', '城市', 'A large town.'),
  'town': _StarterEntry('', '城镇', 'A small city.'),
  'village': _StarterEntry('', '村庄', 'A small group of houses.'),
  'park': _StarterEntry('', '公园', 'An open green space.'),
  'shop': _StarterEntry('', '商店', 'A place that sells things.'),
  'store': _StarterEntry('', '商店', 'A place that sells things.'),
  'school': _StarterEntry('', '学校', 'A place to learn.'),
  'church': _StarterEntry('', '教堂', 'A building for worship.'),
  'farm': _StarterEntry('', '农场', 'A place where food is grown.'),
  'zoo': _StarterEntry('', '动物园', 'A place to see animals.'),
  'office': _StarterEntry('', '办公室', 'A place where people work.'),

  // ── Body parts ────────────────────────────────────────────────────────
  'head': _StarterEntry('', '头', 'The top of the body.'),
  'face': _StarterEntry('', '脸', 'The front of the head.'),
  'hair': _StarterEntry('', '头发', 'What grows on the head.'),
  'eye': _StarterEntry('', '眼睛', 'Used for seeing.'),
  'ear': _StarterEntry('', '耳朵', 'Used for hearing.'),
  'nose': _StarterEntry('', '鼻子', 'Used for smelling.'),
  'mouth': _StarterEntry('', '嘴', 'Used for eating and speaking.'),
  'tooth': _StarterEntry('', '牙齿', 'A hard part in the mouth.'),
  'teeth': _StarterEntry('', '牙齿', 'Plural of "tooth".'),
  'tongue': _StarterEntry('', '舌头', 'The muscle in the mouth.'),
  'lip': _StarterEntry('', '嘴唇', 'The edge of the mouth.'),
  'neck': _StarterEntry('', '脖子', 'The part below the head.'),
  'arm': _StarterEntry('', '手臂', 'From shoulder to hand.'),
  'hand': _StarterEntry('', '手', 'The end of the arm.'),
  'finger': _StarterEntry('', '手指', 'One of the parts of a hand.'),
  'thumb': _StarterEntry('', '拇指', 'The shortest, thickest finger.'),
  'leg': _StarterEntry('', '腿', 'Used for walking.'),
  'knee': _StarterEntry('', '膝盖', 'The middle of the leg.'),
  'foot': _StarterEntry('', '脚', 'The end of the leg.'),
  'feet': _StarterEntry('', '脚', 'Plural of "foot".'),
  'toe': _StarterEntry('', '脚趾', 'One of the parts of a foot.'),
  'body': _StarterEntry('', '身体', 'A person\'s physical form.'),
  'skin': _StarterEntry('', '皮肤', 'The cover of the body.'),
  'heart': _StarterEntry('', '心', 'The organ that pumps blood.'),
  'tummy': _StarterEntry('', '肚子', 'The belly.'),
  'belly': _StarterEntry('', '肚子', 'The middle of the body.'),
  'back': _StarterEntry('', '背', 'The opposite of the front.'),

  // ── Clothes ───────────────────────────────────────────────────────────
  'shirt': _StarterEntry('', '衬衫', 'A top piece of clothing.'),
  'dress': _StarterEntry('', '连衣裙', 'A one-piece garment.'),
  'coat': _StarterEntry('', '外套', 'A warm outer garment.'),
  'jacket': _StarterEntry('', '夹克', 'A short coat.'),
  'pants': _StarterEntry('', '裤子', 'Clothing for the legs.'),
  'shoe': _StarterEntry('', '鞋', 'Footwear.'),
  'sock': _StarterEntry('', '袜子', 'Worn on the foot under shoes.'),
  'hat': _StarterEntry('', '帽子', 'Worn on the head.'),
  'cap': _StarterEntry('', '帽子', 'A soft hat.'),
  'glove': _StarterEntry('', '手套', 'Covers for the hands.'),
  'scarf': _StarterEntry('', '围巾', 'Worn around the neck.'),

  // ── Times / days / months ─────────────────────────────────────────────
  'day': _StarterEntry('', '天；白天', '24 hours; or the time of light.'),
  'night': _StarterEntry('', '夜晚', 'The time of darkness.'),
  'morning': _StarterEntry('', '早上', 'The early part of the day.'),
  'afternoon': _StarterEntry('', '下午', 'The middle part of the day.'),
  'evening': _StarterEntry('', '晚上', 'The end part of the day.'),
  'today': _StarterEntry('', '今天', 'On this day.'),
  'yesterday': _StarterEntry('', '昨天', 'The day before today.'),
  'tomorrow': _StarterEntry('', '明天', 'The day after today.'),
  'now': _StarterEntry('', '现在', 'At this time.'),
  'then': _StarterEntry('', '然后；那时', 'After that; at that time.'),
  'soon': _StarterEntry('', '很快', 'In a short time.'),
  'later': _StarterEntry('', '后来', 'After some time.'),
  'always': _StarterEntry('', '总是', 'At every time.'),
  'never': _StarterEntry('', '从不', 'At no time.'),
  'often': _StarterEntry('', '经常', 'Many times.'),
  'sometimes': _StarterEntry('', '有时', 'Now and then.'),
  'usually': _StarterEntry('', '通常', 'Most often.'),
  'again': _StarterEntry('', '再次', 'One more time.'),
  'still': _StarterEntry('', '仍然', 'Continuing.'),
  'just': _StarterEntry('', '刚刚；只是', 'Very recently; or only.'),
  'time': _StarterEntry('', '时间', 'Hours, minutes, and seconds.'),
  'hour': _StarterEntry('', '小时', '60 minutes.'),
  'minute': _StarterEntry('', '分钟', '60 seconds.'),
  'second': _StarterEntry('', '秒；第二', 'A unit of time; or 2nd.'),
  'week': _StarterEntry('', '星期', 'Seven days.'),
  'month': _StarterEntry('', '月', '~30 days.'),
  'year': _StarterEntry('', '年', '365 days.'),
  'monday': _StarterEntry('', '星期一', 'First weekday.'),
  'tuesday': _StarterEntry('', '星期二', 'Second weekday.'),
  'wednesday': _StarterEntry('', '星期三', 'Third weekday.'),
  'thursday': _StarterEntry('', '星期四', 'Fourth weekday.'),
  'friday': _StarterEntry('', '星期五', 'Fifth weekday.'),
  'saturday': _StarterEntry('', '星期六', 'Sixth weekday.'),
  'sunday': _StarterEntry('', '星期日', 'Seventh weekday.'),
  'january': _StarterEntry('', '一月', 'First month.'),
  'february': _StarterEntry('', '二月', 'Second month.'),
  'march': _StarterEntry('', '三月', 'Third month.'),
  'april': _StarterEntry('', '四月', 'Fourth month.'),
  'june': _StarterEntry('', '六月', 'Sixth month.'),
  'july': _StarterEntry('', '七月', 'Seventh month.'),
  'august': _StarterEntry('', '八月', 'Eighth month.'),
  'september': _StarterEntry('', '九月', 'Ninth month.'),
  'october': _StarterEntry('', '十月', 'Tenth month.'),
  'november': _StarterEntry('', '十一月', 'Eleventh month.'),
  'december': _StarterEntry('', '十二月', 'Twelfth month.'),
  'spring': _StarterEntry('', '春天', 'The season after winter.'),
  'summer': _StarterEntry('', '夏天', 'The hot season.'),
  'autumn': _StarterEntry('', '秋天', 'The season of falling leaves.'),
  'winter': _StarterEntry('', '冬天', 'The cold season.'),
  'birthday': _StarterEntry('', '生日', 'The day someone was born.'),

  // ── Numbers ──────────────────────────────────────────────────────────
  'zero': _StarterEntry('', '零', 'Number 0.'),
  'one': _StarterEntry('', '一', 'Number 1.'),
  'two': _StarterEntry('', '二', 'Number 2.'),
  'three': _StarterEntry('', '三', 'Number 3.'),
  'four': _StarterEntry('', '四', 'Number 4.'),
  'five': _StarterEntry('', '五', 'Number 5.'),
  'six': _StarterEntry('', '六', 'Number 6.'),
  'seven': _StarterEntry('', '七', 'Number 7.'),
  'eight': _StarterEntry('', '八', 'Number 8.'),
  'nine': _StarterEntry('', '九', 'Number 9.'),
  'ten': _StarterEntry('', '十', 'Number 10.'),
  'eleven': _StarterEntry('', '十一', 'Number 11.'),
  'twelve': _StarterEntry('', '十二', 'Number 12.'),
  'thirteen': _StarterEntry('', '十三', 'Number 13.'),
  'fourteen': _StarterEntry('', '十四', 'Number 14.'),
  'fifteen': _StarterEntry('', '十五', 'Number 15.'),
  'sixteen': _StarterEntry('', '十六', 'Number 16.'),
  'seventeen': _StarterEntry('', '十七', 'Number 17.'),
  'eighteen': _StarterEntry('', '十八', 'Number 18.'),
  'nineteen': _StarterEntry('', '十九', 'Number 19.'),
  'twenty': _StarterEntry('', '二十', 'Number 20.'),
  'thirty': _StarterEntry('', '三十', 'Number 30.'),
  'forty': _StarterEntry('', '四十', 'Number 40.'),
  'fifty': _StarterEntry('', '五十', 'Number 50.'),
  'sixty': _StarterEntry('', '六十', 'Number 60.'),
  'seventy': _StarterEntry('', '七十', 'Number 70.'),
  'eighty': _StarterEntry('', '八十', 'Number 80.'),
  'ninety': _StarterEntry('', '九十', 'Number 90.'),
  'hundred': _StarterEntry('', '一百', 'Number 100.'),
  'thousand': _StarterEntry('', '一千', 'Number 1000.'),
  'million': _StarterEntry('', '一百万', 'Number 1,000,000.'),
  'first': _StarterEntry('', '第一', 'Number 1st.'),
  'third': _StarterEntry('', '第三', 'Number 3rd.'),
  'fourth': _StarterEntry('', '第四', 'Number 4th.'),
  'fifth': _StarterEntry('', '第五', 'Number 5th.'),

  // ── Colours ──────────────────────────────────────────────────────────
  'red': _StarterEntry('', '红色', 'The colour of fire.'),
  'blue': _StarterEntry('', '蓝色', 'The colour of the sky.'),
  'green': _StarterEntry('', '绿色', 'The colour of grass.'),
  'yellow': _StarterEntry('', '黄色', 'The colour of the sun.'),
  'purple': _StarterEntry('', '紫色', 'A mix of red and blue.'),
  'pink': _StarterEntry('', '粉色', 'Light red.'),
  'brown': _StarterEntry('', '棕色', 'The colour of wood.'),
  'black': _StarterEntry('', '黑色', 'The darkest colour.'),
  'white': _StarterEntry('', '白色', 'The colour of snow.'),
  'grey': _StarterEntry('', '灰色', 'A mix of black and white.'),
  'gray': _StarterEntry('', '灰色', 'A mix of black and white.'),
  'gold': _StarterEntry('', '金色', 'A shiny yellow.'),
  'silver': _StarterEntry('', '银色', 'A shiny grey.'),
  'colour': _StarterEntry('', '颜色', 'How something looks.'),
  'color': _StarterEntry('', '颜色', 'How something looks.'),

  // ── Adjectives ────────────────────────────────────────────────────────
  'good': _StarterEntry('', '好的', 'Pleasing or right.'),
  'better': _StarterEntry('', '更好的', 'Comparative of "good".'),
  'best': _StarterEntry('', '最好的', 'Superlative of "good".'),
  'bad': _StarterEntry('', '坏的', 'Not good.'),
  'worse': _StarterEntry('', '更坏的', 'More bad.'),
  'worst': _StarterEntry('', '最坏的', 'Most bad.'),
  'big': _StarterEntry('', '大', 'Large in size.'),
  'small': _StarterEntry('', '小', 'Little in size.'),
  'large': _StarterEntry('', '大', 'Big.'),
  'little': _StarterEntry('', '小', 'Small.'),
  'long': _StarterEntry('', '长的', 'Of great length.'),
  'short': _StarterEntry('', '短的；矮的', 'Not long; not tall.'),
  'tall': _StarterEntry('', '高的', 'Of great height.'),
  'high': _StarterEntry('', '高的', 'Far above the ground.'),
  'low': _StarterEntry('', '低的', 'Near the ground.'),
  'old': _StarterEntry('', '老的；旧的', 'Aged; not new.'),
  'young': _StarterEntry('', '年轻的', 'Not yet old.'),
  'new': _StarterEntry('', '新的', 'Not old.'),
  'hot': _StarterEntry('', '热的', 'Very warm.'),
  'cold': _StarterEntry('', '冷的', 'Very chilly.'),
  'warm': _StarterEntry('', '温暖的', 'Slightly hot.'),
  'cool': _StarterEntry('', '凉的；酷的', 'Slightly cold; or nice.'),
  'dry': _StarterEntry('', '干的', 'Not wet.'),
  'wet': _StarterEntry('', '湿的', 'Covered in water.'),
  'fast': _StarterEntry('', '快的', 'Moving quickly.'),
  'slow': _StarterEntry('', '慢的', 'Not fast.'),
  'happy': _StarterEntry('', '高兴的', 'Feeling good.'),
  'sad': _StarterEntry('', '伤心的', 'Feeling unhappy.'),
  'angry': _StarterEntry('', '生气的', 'Feeling mad.'),
  'kind': _StarterEntry('', '友善的', 'Friendly and good.'),
  'mean': _StarterEntry('', '凶的；意思', 'Unkind; or have a meaning.'),
  'nice': _StarterEntry('', '好的', 'Pleasant.'),
  'beautiful': _StarterEntry('', '美丽的', 'Very pretty.'),
  'pretty': _StarterEntry('', '漂亮的', 'Lovely to look at.'),
  'ugly': _StarterEntry('', '丑的', 'Not nice to look at.'),
  'clean': _StarterEntry('', '干净的', 'Not dirty.'),
  'dirty': _StarterEntry('', '脏的', 'Not clean.'),
  'full': _StarterEntry('', '满的', 'Holding all it can.'),
  'empty': _StarterEntry('', '空的', 'Holding nothing.'),
  'easy': _StarterEntry('', '容易的', 'Not hard.'),
  'hard': _StarterEntry('', '难的；硬的', 'Difficult; or firm.'),
  'soft': _StarterEntry('', '软的', 'Not hard.'),
  'light': _StarterEntry('', '亮的；轻的', 'Not dark; or not heavy.'),
  'dark': _StarterEntry('', '黑暗的', 'Without light.'),
  'heavy': _StarterEntry('', '重的', 'Hard to lift.'),
  'strong': _StarterEntry('', '强壮的', 'Having power.'),
  'weak': _StarterEntry('', '弱的', 'Not strong.'),
  'tired': _StarterEntry('', '累的', 'Needing rest.'),
  'sleepy': _StarterEntry('', '困的', 'Wanting to sleep.'),
  'hungry': _StarterEntry('', '饿的', 'Wanting food.'),
  'thirsty': _StarterEntry('', '渴的', 'Wanting drink.'),
  'sick': _StarterEntry('', '生病的', 'Not feeling well.'),
  'well': _StarterEntry('', '好；井', 'Healthy; or a water hole.'),
  'right': _StarterEntry('', '对的；右', 'Correct; or the opposite of left.'),
  'wrong': _StarterEntry('', '错的', 'Not correct.'),
  'true': _StarterEntry('', '真的', 'Real.'),
  'false': _StarterEntry('', '假的', 'Not true.'),
  'real': _StarterEntry('', '真实的', 'Actually existing.'),
  'fake': _StarterEntry('', '假的', 'Not real.'),
  'important': _StarterEntry('', '重要的', 'Mattering a lot.'),
  'special': _StarterEntry('', '特别的', 'Not ordinary.'),
  'funny': _StarterEntry('', '有趣的', 'Making people laugh.'),
  'scary': _StarterEntry('', '可怕的', 'Frightening.'),
  'safe': _StarterEntry('', '安全的', 'Free from danger.'),
  'brave': _StarterEntry('', '勇敢的', 'Not afraid.'),
  'smart': _StarterEntry('', '聪明的', 'Clever.'),
  'loud': _StarterEntry('', '响亮的', 'Making a lot of noise.'),
  'quiet': _StarterEntry('', '安静的', 'Making no noise.'),
  'gentle': _StarterEntry('', '温柔的', 'Soft and kind.'),
  'bright': _StarterEntry('', '明亮的', 'Full of light.'),

  // ── Common adverbs / interjections ─────────────────────────────────────
  'very': _StarterEntry('', '非常', 'To a great degree.'),
  'too': _StarterEntry('', '太；也', 'Excessively; or also.'),
  'also': _StarterEntry('', '也', 'In addition.'),
  'maybe': _StarterEntry('', '也许', 'Perhaps.'),
  'really': _StarterEntry('', '真的', 'Truly.'),
  'almost': _StarterEntry('', '几乎', 'Nearly.'),
  'enough': _StarterEntry('', '足够', 'Sufficient.'),
  'together': _StarterEntry('', '一起', 'With each other.'),
  'alone': _StarterEntry('', '独自', 'By oneself.'),
  'yes': _StarterEntry('', '是的', 'Affirmative.'),
  'okay': _StarterEntry('', '好的', 'All right.'),
  'ok': _StarterEntry('', '好的', 'All right.'),
  'please': _StarterEntry('', '请', 'Polite request word.'),
  'thanks': _StarterEntry('', '谢谢', 'Short for "thank you".'),
  'hello': _StarterEntry('', '你好', 'A greeting.'),
  'hi': _StarterEntry('', '你好', 'Informal greeting.'),
  'goodbye': _StarterEntry('', '再见', 'A farewell.'),
  'bye': _StarterEntry('', '再见', 'Informal farewell.'),
  'oh': _StarterEntry('', '哦', 'A sound of surprise.'),
  'wow': _StarterEntry('', '哇', 'An exclamation of awe.'),

  // ── Misc useful nouns ────────────────────────────────────────────────
  'name': _StarterEntry('', '名字', 'What someone is called.'),
  'word': _StarterEntry('', '单词', 'A unit of language.'),
  'thing': _StarterEntry('', '东西', 'An object.'),
  'way': _StarterEntry('', '方法；路', 'A method; or a path.'),
  'place': _StarterEntry('', '地方', 'A location.'),
  'side': _StarterEntry('', '边', 'An edge.'),
  'top': _StarterEntry('', '顶部', 'The highest part.'),
  'bottom': _StarterEntry('', '底部', 'The lowest part.'),
  'end': _StarterEntry('', '结束；末端', 'A finish or last part.'),
  'beginning': _StarterEntry('', '开始', 'The start.'),
  'middle': _StarterEntry('', '中间', 'The centre.'),
  'front': _StarterEntry('', '前面', 'The opposite of back.'),
  'air': _StarterEntry('', '空气', 'What we breathe.'),
  'sound': _StarterEntry('', '声音', 'Something we hear.'),
  'noise': _StarterEntry('', '噪音', 'Loud sound.'),
  'music': _StarterEntry('', '音乐', 'Pleasant sound.'),
  'song': _StarterEntry('', '歌', 'Words set to music.'),
  'story': _StarterEntry('', '故事', 'A tale.'),
  'game': _StarterEntry('', '游戏', 'Something children play.'),
  'fun': _StarterEntry('', '乐趣', 'Enjoyment.'),
  'idea': _StarterEntry('', '想法', 'A thought.'),
  'dream': _StarterEntry('', '梦', 'Pictures in your mind during sleep.'),
  'world': _StarterEntry('', '世界', 'The earth.'),
  'life': _StarterEntry('', '生活', 'Being alive.'),
  'money': _StarterEntry('', '钱', 'Coins and notes.'),
  'gift': _StarterEntry('', '礼物', 'A present.'),
  'present': _StarterEntry('', '礼物；现在的', 'A gift; or right now.'),
  'surprise': _StarterEntry('', '惊喜', 'An unexpected event.'),
  'job': _StarterEntry('', '工作', 'Paid work.'),

  // ── Picture-book sights ──────────────────────────────────────────────
  'centre': _StarterEntry('', '中心', 'The middle (UK).'),
  'center': _StarterEntry('', '中心', 'The middle (US).'),
  'greenhouse': _StarterEntry('', '温室', 'A glass building for plants.'),
  'rocket': _StarterEntry('', '火箭', 'A space vehicle.'),
  'spaceship': _StarterEntry('', '宇宙飞船', 'A ship for space travel.'),
  'planet': _StarterEntry('', '行星', 'A world in space.'),
  'mars': _StarterEntry('', '火星', 'The Red Planet.'),
  'earth': _StarterEntry('', '地球', 'Our planet.'),
  'space': _StarterEntry('', '太空；空间', 'The area outside Earth; or room.'),

  // ── Common picture-book character names (kept as proper nouns) ────────
  'biff': _StarterEntry('', '比夫', 'A character name in picture books.'),
  'chip': _StarterEntry('', '奇普；薯条', 'A character name; or a thin slice of potato.'),
  'kipper': _StarterEntry('', '基普', 'A character name in picture books.'),
  'wilf': _StarterEntry('', '威尔夫', 'A character name in picture books.'),
  'wilma': _StarterEntry('', '威尔玛', 'A character name in picture books.'),
  'anneena': _StarterEntry('', '安妮娜', 'A character name in picture books.'),
};

class _StarterEntry {
  const _StarterEntry(this.pinyin, this.chinese, this.definition);
  final String pinyin;
  final String chinese;
  final String definition;
}

Future<int> main(List<String> args) async {
  // Parse arguments. Supported invocations:
  //   dart run tool/build_dict.dart                          (starter)
  //   dart run tool/build_dict.dart --starter                (starter)
  //   dart run tool/build_dict.dart --full <ecdict.csv>      (full)
  //   dart run tool/build_dict.dart <ecdict.csv>             (legacy = full)
  String? csvPath;
  var starter = false;
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--starter') {
      starter = true;
    } else if (a == '--full') {
      if (i + 1 >= args.length) {
        stderr.writeln('--full requires a path argument.');
        return 2;
      }
      csvPath = args[i + 1];
      i++;
    } else if (a.startsWith('--')) {
      stderr.writeln('Unknown flag: $a');
      return 2;
    } else {
      csvPath = a;
    }
  }
  if (starter) csvPath = null;

  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  final dest = File(p.absolute(dbRelPath));
  await dest.parent.create(recursive: true);
  if (await dest.exists()) await dest.delete();

  // Also wipe the sqflite_common_ffi cache copy, since it remaps relative paths.
  final cached = File(
    p.join(
      Directory.current.path,
      '.dart_tool',
      'sqflite_common_ffi',
      'databases',
      'assets',
      'dict',
      'ecdict.db',
    ),
  );
  if (await cached.exists()) await cached.delete();

  final db = await factory.openDatabase(
    dest.path,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE entries (
            word       TEXT PRIMARY KEY,
            pinyin     TEXT NOT NULL DEFAULT '',
            chinese    TEXT NOT NULL DEFAULT '',
            definition TEXT NOT NULL DEFAULT '',
            detail     TEXT NOT NULL DEFAULT ''
          )
        ''');
      },
    ),
  );

  var inserted = 0;
  if (csvPath == null) {
    stdout.writeln(
      'No CSV provided — building STARTER dictionary (${_starter.length} entries).',
    );
    await db.transaction((txn) async {
      for (final entry in _starter.entries) {
        await txn.insert('entries', <String, Object?>{
          'word': entry.key,
          'pinyin': entry.value.pinyin,
          'chinese': entry.value.chinese,
          'definition': entry.value.definition,
          'detail': '', // starter dictionary ships without example sentences
        });
        inserted++;
      }
    });
  } else {
    stdout.writeln('Building FULL dictionary from $csvPath …');
    final csv = File(csvPath);
    if (!await csv.exists()) {
      stderr.writeln('CSV not found: $csvPath');
      await db.close();
      return 1;
    }
    stdout.writeln('Reading ${csv.path} …');
    final lines = await csv.readAsLines();
    if (lines.isEmpty) {
      stderr.writeln('CSV is empty.');
      await db.close();
      return 1;
    }
    final header = _splitCsvRow(lines.first).map((c) => c.toLowerCase()).toList();
    final iWord = header.indexOf('word');
    final iPhon = header.indexOf('phonetic');
    final iTrans = header.indexOf('translation');
    final iDef = header.indexOf('definition');
    final iDetail = header.indexOf('detail');
    if (iWord < 0 || iTrans < 0) {
      stderr.writeln('CSV is missing required columns "word" and/or "translation".');
      await db.close();
      return 1;
    }

    await db.transaction((txn) async {
      for (var i = 1; i < lines.length; i++) {
        final line = lines[i];
        if (line.trim().isEmpty) continue;
        final cells = _splitCsvRow(line);
        if (cells.length <= iWord) continue;
        final word = cells[iWord].trim().toLowerCase();
        if (word.isEmpty || word.contains(' ')) continue; // skip phrases
        final pinyin = (iPhon >= 0 && iPhon < cells.length) ? cells[iPhon].trim() : '';
        final chineseRaw = (iTrans >= 0 && iTrans < cells.length) ? cells[iTrans].trim() : '';
        final defRaw = (iDef >= 0 && iDef < cells.length) ? cells[iDef].trim() : '';
        final detailRaw =
            (iDetail >= 0 && iDetail < cells.length) ? cells[iDetail].trim() : '';
        final chinese = chineseRaw.replaceAll(r'\n', '; ').replaceAll('\n', '; ');
        final definition = defRaw.replaceAll(r'\n', '; ').replaceAll('\n', '; ');
        if (chinese.isEmpty && definition.isEmpty) continue;
        await txn.insert(
          'entries',
          <String, Object?>{
            'word': word,
            'pinyin': pinyin,
            'chinese': chinese,
            'definition': definition,
            'detail': detailRaw,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        inserted++;
        if (inserted % 10000 == 0) {
          stdout.writeln('  inserted $inserted rows …');
        }
      }
    });
  }

  // Always inject digit + ordinal entries last (overwrites any CSV-supplied
  // numerics so the picture-book child-friendly Chinese always wins).
  var extras = 0;
  await db.transaction((txn) async {
    for (final entry in _numericExtras.entries) {
      await txn.insert(
        'entries',
        <String, Object?>{
          'word': entry.key,
          'pinyin': '',
          'chinese': entry.value.chinese,
          'definition': entry.value.definition,
          'detail': '',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      extras++;
    }
  });
  inserted += extras;
  stdout.writeln('  injected $extras numeric extras.');

  await db.execute('CREATE INDEX IF NOT EXISTS idx_word ON entries(word)');
  await db.close();

  final size = await dest.length();
  stdout.writeln('OK. $inserted entries written to ${dest.path} (${(size / 1024).toStringAsFixed(1)} KB).');
  return 0;
}

/// Digits ("3", "12", …) and ordinals ("1st", "2nd", …). Always injected at
/// the tail of every build so tapping a number in the reader resolves to its
/// Chinese reading.
const Map<String, _StarterEntry> _numericExtras = {
  '0': _StarterEntry('', '零', 'Number 0.'),
  '1': _StarterEntry('', '一', 'Number 1.'),
  '2': _StarterEntry('', '二', 'Number 2.'),
  '3': _StarterEntry('', '三', 'Number 3.'),
  '4': _StarterEntry('', '四', 'Number 4.'),
  '5': _StarterEntry('', '五', 'Number 5.'),
  '6': _StarterEntry('', '六', 'Number 6.'),
  '7': _StarterEntry('', '七', 'Number 7.'),
  '8': _StarterEntry('', '八', 'Number 8.'),
  '9': _StarterEntry('', '九', 'Number 9.'),
  '10': _StarterEntry('', '十', 'Number 10.'),
  '11': _StarterEntry('', '十一', 'Number 11.'),
  '12': _StarterEntry('', '十二', 'Number 12.'),
  '13': _StarterEntry('', '十三', 'Number 13.'),
  '14': _StarterEntry('', '十四', 'Number 14.'),
  '15': _StarterEntry('', '十五', 'Number 15.'),
  '16': _StarterEntry('', '十六', 'Number 16.'),
  '17': _StarterEntry('', '十七', 'Number 17.'),
  '18': _StarterEntry('', '十八', 'Number 18.'),
  '19': _StarterEntry('', '十九', 'Number 19.'),
  '20': _StarterEntry('', '二十', 'Number 20.'),
  '21': _StarterEntry('', '二十一', 'Number 21.'),
  '22': _StarterEntry('', '二十二', 'Number 22.'),
  '25': _StarterEntry('', '二十五', 'Number 25.'),
  '30': _StarterEntry('', '三十', 'Number 30.'),
  '40': _StarterEntry('', '四十', 'Number 40.'),
  '50': _StarterEntry('', '五十', 'Number 50.'),
  '60': _StarterEntry('', '六十', 'Number 60.'),
  '70': _StarterEntry('', '七十', 'Number 70.'),
  '80': _StarterEntry('', '八十', 'Number 80.'),
  '90': _StarterEntry('', '九十', 'Number 90.'),
  '100': _StarterEntry('', '一百', 'Number 100.'),
  '1000': _StarterEntry('', '一千', 'Number 1000.'),
  '10000': _StarterEntry('', '一万', 'Number 10 000.'),
  // Ordinals
  '1st': _StarterEntry('', '第一', '1st (first).'),
  '2nd': _StarterEntry('', '第二', '2nd (second).'),
  '3rd': _StarterEntry('', '第三', '3rd (third).'),
  '4th': _StarterEntry('', '第四', '4th (fourth).'),
  '5th': _StarterEntry('', '第五', '5th (fifth).'),
  '6th': _StarterEntry('', '第六', '6th (sixth).'),
  '7th': _StarterEntry('', '第七', '7th (seventh).'),
  '8th': _StarterEntry('', '第八', '8th (eighth).'),
  '9th': _StarterEntry('', '第九', '9th (ninth).'),
  '10th': _StarterEntry('', '第十', '10th (tenth).'),
};

/// Very small RFC-4180-ish CSV row splitter — supports quoted fields containing
/// commas and the escaped double-quote `""`. ECDICT CSVs use this style.
List<String> _splitCsvRow(String row) {
  final out = <String>[];
  final buf = StringBuffer();
  var inQuotes = false;
  for (var i = 0; i < row.length; i++) {
    final c = row[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < row.length && row[i + 1] == '"') {
          buf.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        buf.write(c);
      }
    } else {
      if (c == ',') {
        out.add(buf.toString());
        buf.clear();
      } else if (c == '"') {
        inQuotes = true;
      } else {
        buf.write(c);
      }
    }
  }
  out.add(buf.toString());
  return out;
}
