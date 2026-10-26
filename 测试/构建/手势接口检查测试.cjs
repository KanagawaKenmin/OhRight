// 测试边界：拦截 UIKit/SwiftUI 手势协议误用，不启动 App 或云构建。
// 输入：小型 Swift 源码样本；输出：错误数量和位置断言。
const test = require('node:test');
const assert = require('node:assert/strict');
const { checkGestureInterfaces } = require('../../构建/检查手势接口.cjs');
const declaration = 'struct BackgroundTap: UIGestureRecognizerRepresentable {}';
const check = source => checkGestureInterfaces({ '桥接.swift': declaration, '首页.swift': source });

test('reject UIKit recognizer passed directly to simultaneousGesture', () => {
  const errors = check('view\n.simultaneousGesture(BackgroundTap())');
  assert.equal(errors.length, 1);
  assert.equal(errors[0].file, '首页.swift');
  assert.equal(errors[0].line, 2);
});
test('reject explicitly typed bridge property and function used in composition', () => {
  assert.equal(check('var tap: BackgroundTap { BackgroundTap() }\nview.simultaneousGesture(tap)').length, 1);
  assert.equal(check('func tap() -> BackgroundTap { BackgroundTap() }\nview.highPriorityGesture(tap())').length, 1);
});
test('accept official gesture overload and ordinary SwiftUI gestures', () => {
  assert.deepEqual(check('view.gesture(BackgroundTap()).simultaneousGesture(TapGesture())'), []);
});
test('accept commented examples without treating them as active calls', () => {
  assert.deepEqual(check('// .simultaneousGesture(BackgroundTap())\nview.gesture(BackgroundTap())'), []);
});
test('recognize representable declared after other protocols', () => {
  const errors = checkGestureInterfaces({ '手势.swift': 'struct Bridge: CustomProtocol, UIGestureRecognizerRepresentable {}',
    '页面.swift': 'view.highPriorityGesture(Bridge())' });
  assert.equal(errors.length, 1);
});
