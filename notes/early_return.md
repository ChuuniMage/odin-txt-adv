
Early return/continue from a function/scope is useful to save indent space and perhaps even instructions.

```go
function :: proc (cond:bool) {
    if cond == false {
        return
    }    
    fmt.printf("It was true!)
}
```

It's useful if you want to gate by multiple conditions, or 