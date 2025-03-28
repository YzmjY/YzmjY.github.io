
---
date: 2024-11-22
categories:
  - 刷题
draft: false
---
# Stack

<!-- more -->

## 相关算法
### 单调栈
单调栈：栈内元素单调递增或递减，通常用来查找左侧或右侧第一个更大或更小的元素。
#### 左侧
用单调栈来解决查找左侧元素问题时，关注点应该在栈顶元素与次顶元素。
- 查找左侧第一个更大元素：
```cpp
vector<int> stackAlgo(const vector<int>& arr) {
	stack<int> stk;
	vector<int> res(arr.size(), -1);

	for (int i = 0; i < arr.size(); ++i) {
		// 递减单调栈
		while (!stk.empty() && arr[stk.top()] <= arr[i]) {
			int top = stk.top();
			stk.pop();
			if (stk.empty()) {
				break;
			}
			int temp = stk.top();
			// top的左侧第一个比top大的元素
			res[top] = arr[temp];
		}
		stk.push(i);
	}
	while (!stk.empty()) {
		int top = stk.top();
		stk.pop();
		if (stk.empty()) {
			break;
		}
		int temp = stk.top();
		res[top] = arr[temp];
	}
	return res;
}
```
- 查找左侧第一个更小元素：
```cpp
vector<int> stackAlgo(const vector<int>& arr) {
	stack<int> stk;
	vector<int> res(arr.size(), -1);
	print("init", arr);

	for (int i = 0; i < arr.size(); ++i) {
		// 递增单调栈, 等号也应该处理，因为i一定是更大的
		while (!stk.empty() && arr[stk.top()] >= arr[i]) {
			int top = stk.top();
			stk.pop();
			if (stk.empty()) {
				break;
			}
			int temp = stk.top();
			// top的左侧第一个比top小的元素
			res[top] = arr[temp];
		}
		stk.push(i);
	}
	while (!stk.empty()) {
		int top = stk.top();
		stk.pop();
		if (stk.empty()) {
			break;
		}
		int temp = stk.top();
		res[top] = arr[temp];
	}
	return res;
}
```
#### 右侧
用单调栈来解决查找右侧元素问题时，关注点应该在栈顶元素与待入栈元素。
- 查找右侧第一个更大元素：
```cpp
vector<int> stackAlgo(const vector<int>& arr) {
	stack<int> stk;
	vector<int> res(arr.size(), -1);

	for (int i = 0; i < arr.size(); ++i) {
		// 递增单调栈
		while (!stk.empty() && arr[stk.top()] < arr[i]) {
			int top = stk.top();
			stk.pop();
			// arr[i]即为arr[top]的下一个更小元素
			res[top] = arr[i]; // 记录结果
		}
		stk.push(i);
	}
	return res;
}
```

- 查找右侧第一个更小元素：
```cpp
vector<int> stackAlgo(const vector<int>& arr) {
	stack<int> stk;
	vector<int> res(arr.size(), -1);
	print("init", arr);

	for (int i = 0; i < arr.size(); ++i) {
		// 递增单调栈
		while (!stk.empty() && arr[stk.top()] > arr[i]) {
			int top = stk.top();
			stk.pop();
			// arr[i]即为arr[top]的下一个更小元素
			res[top] = arr[i]; // 记录结果
		}
		stk.push(i);
	}
	return res;
}
```