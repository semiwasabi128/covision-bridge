// 單元測試：BridgeTokens
// 驗證 85 個 tokens 命名和 hex 格式

import { BridgeTokens, bridgeToken, BRIDGE_TOKEN_COUNT } from '../src/tokens';

describe('BridgeTokens', () => {
  test('包含完整 85 個 tokens', () => {
    expect(Object.keys(BridgeTokens).length).toBe(BRIDGE_TOKEN_COUNT);
  });

  test('所有 token 都有合法 hex 值', () => {
    for (const [name, hex] of Object.entries(BridgeTokens)) {
      expect(hex, name).toMatch(/^#[0-9A-Fa-f]{6}$|^#[0-9A-Fa-f]{8}$/);
    }
  });

  test('canvas 應為最深的黑色', () => {
    expect(BridgeTokens.canvas).toBe('#07080A');
  });

  test('textPrimary 應為純白', () => {
    expect(BridgeTokens.textPrimary).toBe('#F9F9F9');
  });
});

describe('bridgeToken helper', () => {
  test('直接回傳 hex（無 opacity）', () => {
    expect(bridgeToken('canvas')).toBe('#07080A');
  });

  test('with opacity → rgba', () => {
    expect(bridgeToken('textPrimary', 0.5)).toMatch(/rgba\(249, 249, 249,/);
  });

  test('對 8 位 hex token 套 opacity', () => {
    // borderSubtle = '#0DFFFFFF' (8-digit)
    const result = bridgeToken('borderSubtle', 0.5);
    expect(result).toMatch(/rgba\(255, 255, 255, 0\.0\d/);
  });
});
