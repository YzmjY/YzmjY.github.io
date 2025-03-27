---
date: 2025-03-21
categories:
  - CPP
---

# Concept

Concept 是 CPP20 中新增的概念，用于描述一个类型是否满足某个特定的条件。在 C++20 之前，我们通常使用模板元编程来实现类似的功能(SFINAE)，但是这种方式比较繁琐，而且容易出错。借助 Concept，我们可以更加简洁地实现类似的功能，且报错提示更加友好。

## SFINAE

SFINAE(Substitution Failure Is Not An Error)是一种模板元编程技术，它允许编译器在模板实例化时检查类型是否满足特定的条件。如果类型不满足条件，编译器会忽略该实例化，从而避免编译错误。
SFINAE 的实现方式通常是使用一个特化版本的模板函数，该函数的参数类型为待检查的类型，返回类型为 void。如果该函数的实例化成功，则说明类型满足条件，否则不满足条件。

```cpp
#include <iostream>
#include <type_traits>
#include <vector>

// SFINAE测试: 一个辅助类型（helper type）
template<typename T, typename = void>
struct HasSize : std::false_type {};
i
// 对于有.size()成员函数的类型特化
template<typename T>
struct HasSize<T, std::void_t<decltype(std::declval<T>().size())>> : std::true_type {};

// 仅接受具有.size()成员函数的类型的函数
template<typename T>
typename std::enable_if<HasSize<T>::value, void>::type printSize(const T& container) {
    std::cout << "Size: " << container.size() << std::endl;
}

// 重载的版本，用于那些不具有.size()成员函数的类型
void printSize(...) {
    std::cout << "Type does not have a size." << std::endl;
}

int main() {
    std::vector<int> vec = {1, 2, 3};
    int arr[3] = {1, 2, 3};

    printSize(vec); // 正确: vector有.size()成员函数
    printSize(arr); // 输出: Type does not have a size.
    return 0;
}
```

上述代码中，我们定义了一个辅助类型`HasSize`，它接受一个类型参数`T`和一个可选的类型参数`U`。如果`U`没有被指定，则默认为`void`。`HasSize`是一个模板类，它有一个成员类型`value`，表示类型`T`是否具有`.size()`成员函数。
同时定义了一个`printSize`函数，它接受一个类型为`T`的参数。如果类型`T`具有`.size()`成员函数，则使用`std::enable_if`来启用该重载。如果类型`T`不具有`.size()`成员函数，则使用`...`参数包匹配来启用另一个重载。

> `std::enable_if`是一个在 C++11 中引入的类型 triat，它基于一个编译时布尔表达式，能够在满足条件时启用某个模板特化或函数重载。若条件为真（即，表达式为 true），`std::enable_if` 将有一个名为 `type` 的成员定义，其类型是其第二个模板参数（默认为 `void`）。如果条件为假（即，表达式为 false），则 std::enable_if 没有 `type` 成员，导致替换失败，这也是基于 `SFINAE` 原则实现的。

## Concept

有了 Concept，我们可以更加简洁地实现类似的功能。改写如上代码，使用 Concept 来实现：

```cpp
#include <iostream>
#include <vector>
#include <concepts>

// 定义一个 Concept，检查类型 T 是否具有 .size() 成员函数
template<typename T>
concept HasSize = requires(T t) {
    { t.size() } -> std::convertible_to<std::size_t>;
};

// 使用 HasSize concept 的 printSize 版本，仅接受具有 .size() 成员函数的类型
template<typename T>
requires HasSize<T>
void printSize(const T& container) {
    std::cout << "Size: " << container.size() << std::endl;
}

// 重载的版本，用于所有不满足 HasSize concept 的类型
void printSize(...) {
    std::cout << "Type does not have a size." << std::endl;
}

int main() {
    std::vector<int> vec = {1, 2, 3};
    int arr[3] = {1, 2, 3};

    printSize(vec); // 正确: vector 有 .size() 成员函数
    printSize(arr); // 输出: Type does not have a size.
    return 0;
}
```

### 定义 Concept

一个 Concept 的定义语法如下：

```cpp
template < template-parameter-list >
concept concept-name attr(optional) = constraint-expression;
```

`constraint-expression`可以是对模板参数 `T` 的一系列要求，通常使用标准库中的类型特性`（std::is_integral_v<T>）`等进行检查，或者使用 `requires` 表达式直接描述 T 要支持的操作。

- 简单的类型检查

```cpp
#include <type_traits>

template<typename T>
concept Integral = std::is_integral_v<T>;
```

- 使用 requires 表达式

```
#include <concepts>

template<typename T>
concept HasSize = requires(T t) {
    { t.size() } -> std::convertible_to<std::size_t>;
};
```

#### constraint-expression

[cppreference/constraint](https://en.cppreference.com/w/cpp/language/constraints)

#### requires 表达式

requires 表达式是 C++20 引入的语法，用于描述类型 T 的约束条件。它可以用于类型检查、函数重载、模板参数推导等场景。
requires 的语法如下：

```cpp
requires (parameter-list) {
    requirement-seq
}
```

`parameter-list`是可选的，用于定义 requires 表达式中的参数列表。这些参数没有链接、存储或生命周期，它们仅作为定义`requirement-seq`的注解使用。
`requirement-seq`是一组 requirement，每个 requirement 有如下几种形式之一：

- simple-requirement:
  简单要求是不以关键字 requires 开头的任意表达式语句。它断言表达式有效。表达式是未计算的操作数;仅检查语言正确性。

```cpp
template<typename T>
concept Addable = requires (T a, T b)
{
    a + b; // "the expression “a + b” is a valid expression that will compile"
};

template<class T, class U = T>
concept Swappable = requires(T&& t, U&& u)
{
    swap(std::forward<T>(t), std::forward<U>(u));
    swap(std::forward<U>(u), std::forward<T>(t));
};
```

- type-requirement:
  类型要求是关键字 `typename` 后跟类型名称（可选类型限定符）。该 type-requirement 成立的条件是`typename`后的类型有效：type-requirement 可用于验证一个嵌套类型是否存在，或者一个特化的类模板是否声明了某个类型，或者别名模板特化声明了某个类型。

```cpp
template<typename T>
using Ref = T&;

template<typename T>
concept C = requires
{
    typename T::inner; // required nested member name
    typename S<T>;     // required class template specialization
    typename Ref<T>;   // required alias template substitution
};

template<class T, class U>
using CommonType = std::common_type_t<T, U>;

template<class T, class U>
concept Common = requires (T&& t, U&& u)
{
    typename CommonType<T, U>; // CommonType<T, U> is valid and names a type
    { CommonType<T, U>{std::forward<T>(t)} };
    { CommonType<T, U>{std::forward<U>(u)} };
};
```

- compound-requirement:
  复合 requirement 的基本形式是：

```cpp
{ expression } noexcept(optional) return-type-requirement (optional) ;
return-type-requirement -> type-constraint
```

```cpp
template<typename T>
concept C2 = requires(T x)
{
    // the expression *x must be valid
    // AND the type T::inner must be valid
    // AND the result of *x must be convertible to T::inner
    {*x} -> std::convertible_to<typename T::inner>;

    // the expression x + 1 must be valid
    // AND std::same_as<decltype((x + 1)), int> must be satisfied
    // i.e., (x + 1) must be a prvalue of type int
    {x + 1} -> std::same_as<int>;

    // the expression x * 1 must be valid
    // AND its result must be convertible to T
    {x * 1} -> std::convertible_to<T>;
};
```

- nested-requirement:
  嵌套 requirement 的形式为:

```cpp
requires constraint-expression ;
```

```cpp
template<class T>
concept Semiregular = DefaultConstructible<T> &&
    CopyConstructible<T> && CopyAssignable<T> && Destructible<T> &&
requires(T a, std::size_t n)
{
    requires Same<T*, decltype(&a)>; // nested: "Same<...> evaluates to true"
    { a.~T() } noexcept; // compound: "a.~T()" is a valid expression that doesn't throw
    requires Same<T*, decltype(new T)>; // nested: "Same<...> evaluates to true"
    requires Same<T*, decltype(new T[n])>; // nested
    { delete new T }; // compound
    { delete new T[n] }; // compound
};
```

### 使用 Concept

Concept 可以用于函数模板的参数类型检查，也可以用于类模板的约束。

#### 函数模板

声明一个`Intergral`的 concept，定义如下：

```cpp
template<typename T>
concept Integral = std::is_integral_v<T>;
```

在函数模板中使用 Concept，可以使用 requires 表达式来描述函数的约束条件。有如下几种方式。

- 方式一
  第一种是 Bjarne Stroustrup 最喜欢的，他甚至觉得剩下的几种用法都是多余的，但是众口难调，投票决定，很多东西他也做不了主。来看看这种用法吧，就是用了一个多余的`auto`关键字，来说明`auto`前面的 Integral 是一个`concept`：

```cpp
Integral auto Add(Integral auto a, Integral auto b) {
	return a + b;
}
```

可以用新的格式：

```cpp
Integral auto c = Add(10, 3)
```

来调用，当然也可以用以前的调用方法：

```cpp
int c = Add(10, 3)
```

- 方式二
  再来看第二种，在`template`声明以后紧接着用`requires`关键字说明模板参数需要满足的`concept`，也很直观：

```cpp
template<typename T>;
requires Integral<T>;
T Add(T a, T b){
	return a + b;
}
```

这种用法不必对函数声明中的每个 T 都写成长长的`Integral auto`，当函数参数较多时明显比第一种要好，所以 Bjarne Stroustrup 也不见得是对的，毕竟人都有偏见。

- 方式三
  继续看第三种，这种和第二种的区别就是将`requires Integral<T>`挪动了位置，放在了函数声明的后面，效果是一样的：

```cpp
template<typename T>
T Add(T a, T b) requires Integral<T>{
	return a + b;
}
```

- 方式四
  第四种是省略了`requires`关键字，直接将`concept`的名字放入到模板参数前面，同时也省去了平常模板声明用的`typename`或`class`，其实我觉得这种最直观，如下：

```cpp
template<Integral T>
T Add(T a, T b){
	return a + b;
}
```

`concept`还可用于函数的重载，假设我再加上一个普通的`Add`函数，上面的代码可以编译通过，普通的`Add`函数就和 C++20 之前的函数一样：
template<class T>;
T Add(T a, T b){
return a + b;
}
加了这个函数以后，不满足`Integral`的参数就会调用这个函数，而满足`Integral`的参数会调用之前用`concept`定义的函数。编译器一如既往地选择最匹配的函数。

#### 类模板

声明一个`Printable`的 concept，定义如下：

```cpp
#include <iostream>
#include <concepts>

template<typename T>
concept Printable = requires(T x) {
    { std::cout << x } -> std::convertible_to<std::ostream&>;
};
```

如下所示，在类模板中使用该 concept：

```cpp
template<Printable T>
class Printer {
public:
    void print(const T& value) const {
        std::cout << value << std::endl;
    }
};

template<typename T>
requires Printable<T>
class Printer {
public:
    void print(const T& value) const {
        std::cout << value << std::endl;
    }
};
```
