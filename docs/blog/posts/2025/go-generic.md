---
date: 2025-08-13
categories:
  - Go
slug: go-generic
draft: false
---

# Go 泛型

![](../assert/go.png)
/// caption
///

## 一个例子
```go
// SumIntsOrFloats sums the values of map m. It supports both int64 and float64
// as types for map values.
func SumIntsOrFloats[K comparable, V int64 | float64](m map[K]V) V {
    var s V
    for _, v := range m {
        s += v
    }
    return s
}
```

<!-- more -->

## Go 泛型介绍
Go 从 1.18 开始支持泛型。主要包含以下三个大的特性：

- 类型和函数支持类型参数（Type Parameters）
- 扩展 `interface` 语法，支持定义一组类型的约束
- 类型推断，支持根据函数参数自动推断类型参数

### 类型参数（Type Parameters）
函数或者类型可以接受[类型参数](https://go.dev/ref/spec#Type_parameter_declarations)，用方括号 `[]` 括起来，放在函数名或者类型名的后面。
```go
[P any]
[S interface{ ~[]byte|string }]
[S ~[]E, E any]
[P Constraint[int]]
[_ any]
```

#### 函数的类型参数
函数可以接受类型参数，例如：
```go
func MapKeys[K comparable, V any](m map[K]V) []K {
    r := make([]K, 0, len(m))
    for k := range m {
        r = append(r, k)
    }
    return r
}
```
我们可以通过指定具体的类型参数来实例化这个泛型函数：
```go
func main() {
    f := MapKeys[int, string]
    m := map[int]string{1: "a", 2: "b"}
    keys := f(m)
    fmt.Println(keys) // [1 2]
}
```

#### 类型的类型参数
类型也可以接受类型参数，例如：
```go
type List[T any] struct {
    head, tail *ListNode[T]
}
```
同样，该类型的方法的接收器也可以使用该类型参数：
```go
func (l *List[T]) Append(v T) {
    l.tail.next = &ListNode[T]{val: v}
    l.tail = l.tail.next
}
```

### 类型集（Type Sets）
扩展 `interface` 的语法，支持通过 `interface` 来定义一组类型，形成类型约束（[Type Constraints](https://go.dev/ref/spec#Type_constraints)），例如：
```go
type Number interface {
    int | int8 | int16 | int32 | int64 |
        uint | uint8 | uint16 | uint32 | uint64 | float32 | float64
}
```
此外，对于类型约束，我们有时只关注其底层类型，例如：
```go
type MyInt int
```
`MyInt` 是 `int` 的别名，因此 `MyInt` 也满足 `Number` 接口。可以通过 `~` 来指定底层类型，例如：
```go
type Number interface {
    ~int | ~int8 | ~int16 | ~int32 | ~int64 |
        ~uint | ~uint8 | ~uint16 | ~uint32 | ~uint64 | ~float32 | ~float64
}
```

### 类型推断
#### 函数的类型推断
Go 支持根据函数参数自动推断类型参数，例如：
```go 
func SumIntsOrFloats[K comparable, V int64 | float64](m map[K]V) V {
    var s V
    for _, v := range m {
        s += v
    }
    return s
}
```
我们可以省略类型参数，例如：
```go
func main() {
    m := map[int]int64{1: 1, 2: 2}
    s := SumIntsOrFloats(m)
    fmt.Println(s) // 3
}
```
#### 类型约束的类型推断
```go
// Scale returns a copy of s with each element multiplied by c.
func Scale[S ~[]E, E constraints.Integer](s S, c E) S {
    r := make(S, len(s))
    for i, v := range s {
        r[i] = v * c
    }
    return r
}
```
类型 E 由 `constraints.Integer` 约束，我们下面的调用可以省略参数，Go 可以自动推断。
```go
type Point []int32

func (p Point) String() string {
    // Details not important.
}

// ScaleAndPrint doubles a Point and prints it.
func ScaleAndPrint(p Point) {
    r := Scale(p, 2)
    fmt.Println(r.String()) // DOES NOT COMPILE
}
```
### Tips
- 类型集中的类型不能有方法。下面的代码是无效的：
    ```go
    type Comparable[T any] interface {
        Compare(T) int
    }

    // invalid
    type OrderOrCompare[T any] interface {
        constraints.Ordered | Comparable[T]
    }
    ```
- 内置的一些类型约束，可以在 `golang.org/x/exp/constraints` 包中找到。      
  | 类型约束 | 说明       |
  | -------- | ---------- |
  | Signed   | 有符号整数 |
  | Unsigned | 无符号整数 |
  | Integer  | 整数       |
  | Float    | 浮点数     |
  | Complex  | 复数       |
  | Ordered  | 有序类型   |
