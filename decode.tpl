<html>
    <head>
        <title>[WIP] Bitcoin TX Decoder</title>
    </head>
    <body>
        <form method="POST">
            <textarea name="hex" style="padding:30px;width:100%;height:20%;"></textarea>
            <input type="submit" value="decode">
        </form>
        ::if (tx != null)::
            <p style="max-width:100%;padding:30px;background-color:black;font-family: monospace, monospace;">
            <table style="margin-bottom:30px;">
                ::foreach tx.sections::
                    <tr>
                        <td><span style="color:::color::;">::label:::</span></td>
                        <td><span style="color:::color::;">::human_readable::</span></td>
                    <tr>
                ::end::
            </table>
            ::foreach tx.sections::<span style="color:::color::;word-wrap:break-word;">::hex::</span>::end::
            </p>
        ::end::
    </body>
</html>
