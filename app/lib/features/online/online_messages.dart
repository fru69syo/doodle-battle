import '../../data/backend/backend_models.dart';

/// Gentle kid message for every `registerCharacter` rejection reason
/// (docs/BACKEND.md §6).
const registerRejectionMessages = <String, String>{
  'LEVEL_TOO_LOW': 'レベル5に なったら オンラインで あそべるよ',
  'STATS_INVALID': 'キャラの じょうほうが うまく よめなかったよ。もういちど ためしてね',
  'NAME_INVALID': 'なまえに つかえない もじが あるよ。したの なまえから えらんでね',
  'NAME_NG': 'その なまえは オンラインでは つかえないよ。したの なまえから えらんでね',
  'NAME_PERSONAL_INFO': 'なまえに じぶんの ことが かいてあるかも。したの なまえから えらんでね',
  'IMAGE_VIOLENCE': 'こわい えは オンラインに だせないよ。ほかの えで あそぼう',
  'IMAGE_SEXUAL': 'この えは オンラインに だせないよ。ほかの えで あそぼう',
  'IMAGE_HATE': 'だれかが いやな きもちに なる えは だせないよ',
  'IMAGE_COPYRIGHT': 'ほかの キャラの まねっこは オンラインに だせないよ。じぶんで かんがえた キャラで あそぼう',
  'IMAGE_REAL_PERSON': 'ひとの しゃしんや かおは つかえないよ',
  'IMAGE_PERSONAL_INFO': 'えに なまえや じゅうしょが かいてあるみたい。けしてから もういちど とってね',
  'IMAGE_NOT_DRAWING': 'しゃしんじゃなくて、かみに かいた えで あそぼう',
  'IMAGE_OTHER': 'この えは オンラインに だせなかったよ。ほかの えで ためしてね',
  'TOO_MANY_CHARACTERS': 'オンラインに だせる キャラが いっぱいだよ。おうちのひとに そうだん してね',
};

const _fallback = 'うまく いかなかったよ。あとで また ためしてね';

String registerRejectionMessage(String reason) =>
    registerRejectionMessages[reason] ?? 'この キャラは オンラインに だせなかったよ';

/// Kid message for a [BackendException] code.
String backendErrorMessage(String code) => switch (code) {
  BackendCodes.unavailable => 'じゅんびちゅう',
  BackendCodes.network => 'インターネットに つながって いないみたい。つながる ところで ためしてね',
  BackendCodes.rateLimited => 'ちょっと やすんでから また ためしてね',
  BackendCodes.aiUnavailable => 'いまは しんさが できないよ。あとで ためしてね',
  BackendCodes.consentRequired => 'おうちのひとに オンラインを ゆるして もらってね',
  BackendCodes.snapshotNotActive => 'もういちど とうろく してね',
  BackendCodes.notOwner || BackendCodes.notFound => 'キャラが みつからなかったよ',
  _ => _fallback,
};
