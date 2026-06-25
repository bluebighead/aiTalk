@echo off
chcp 65001 >nul
echo ============================================
echo  AI Talk - 端口转发和防火墙设置
echo  请以管理员身份运行此脚本
echo ============================================
echo.

:: 添加端口转发：把局域网发到 4000 端口的请求转发到本地 Cherry Studio
echo [1/2] 添加端口转发 0.0.0.0:4000 -^> 127.0.0.1:4000 ...
netsh interface portproxy add v4tov4 listenport=4000 listenaddress=0.0.0.0 connectport=4000 connectaddress=127.0.0.1
if %errorlevel% equ 0 (
    echo   ✓ 端口转发添加成功
) else (
    echo   ✗ 失败，请确认已以管理员身份运行
    pause
    exit /b 1
)

:: 添加防火墙规则，放行 4000 端口
echo [2/2] 添加防火墙入站规则（放行 4000 端口）...
netsh advfirewall firewall add rule name="Cherry Studio API 4000" dir=in action=allow protocol=TCP localport=4000
if %errorlevel% equ 0 (
    echo   ✓ 防火墙规则添加成功
) else (
    echo   ✗ 防火墙规则添加失败
)

echo.
echo ============================================
echo  设置完成！请在手机上测试连接：
echo  地址: 192.168.31.13
echo  端口: 4000
echo ============================================
echo.
echo  如需删除端口转发：
echo  netsh interface portproxy delete v4tov4 listenport=4000 listenaddress=0.0.0.0
echo.
pause
