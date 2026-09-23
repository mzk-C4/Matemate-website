const fs = require('fs');
const src = 'D:/大学事情/大一/AIGC/最终PPT/picture/数学资料库+个性化组卷/';
const dst = 'D:/projects/MathMate-Website/images/';
const m = {
  '资料库.jpg': 'library.jpg',
  '六维能力图.jpg': 'exam-radar.jpg',
  '六维能力+题库.jpg': 'exam-radar-bank.jpg',
  '题库1.jpg': 'exam-bank1.jpg',
  '题库2.jpg': 'exam-bank2.jpg',
  '题目.jpg': 'exam-question.jpg'
};
for (const [s, d] of Object.entries(m)) {
  try { fs.copyFileSync(src + s, dst + d); console.log('OK', d, fs.statSync(dst + d).size); }
  catch (e) { console.error('FAIL', s, e.message); }
}
