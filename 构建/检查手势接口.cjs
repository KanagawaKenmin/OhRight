// 构建边界：检查本项目 UIKit 桥接类型被误传给 SwiftUI 手势组合接口。
// 输入：Swift 源文件映射；输出：可定位错误；不替代 Apple SDK 类型检查。
// 依赖：JavaScript 标准库；覆盖构造器及显式类型变量/函数的直接调用。
function checkGestureInterfaces(sources) {
  const clean = text => text.replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g,
    match => match.replace(/[^\n]/g, ' '));
  const files = Object.entries(sources).map(([file, source]) => [file, clean(source)]);
  const types = new Set();
  for (const [, source] of files) {
    for (const match of source.matchAll(/\b(?:struct|class)\s+(\w+)\s*:\s*([^{}\n]+)/g)) {
      if (/\b(?:UI|NS)GestureRecognizerRepresentable\b/.test(match[2])) types.add(match[1]);
    }
  }
  const errors = [];
  for (const [file, source] of files) {
    const bridged = new Set(types);
    for (const match of source.matchAll(/\b(?:let|var)\s+(\w+)\s*:\s*(\w+)|\bfunc\s+(\w+)\([^)]*\)\s*->\s*(\w+)/g)) {
      if (types.has(match[2] || match[4])) bridged.add(match[1] || match[3]);
    }
    for (const match of source.matchAll(/\.(simultaneousGesture|highPriorityGesture)\s*\(\s*(\w+)\b/g)) {
      if (bridged.has(match[2])) errors.push({ file, line: source.slice(0, match.index).split('\n').length,
        text: `${match[2]} is a recognizer representable, not SwiftUI.Gesture; use .gesture(...) instead of .${match[1]}(...)` });
    }
  }
  return errors;
}
module.exports = { checkGestureInterfaces };
