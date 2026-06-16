backend
npm install

atualizar version: x.y.z+w em pubspec.yaml
flutter clean
flutter pub get
flutter build windows --release 

pg_dump -U postgres -d visualpremiumsoftwarerebuild -F c -f "C:\Backup\visualpremiumsoftwarerebuild.backup"


-> para acessar a database psql -U postgres -d visualpremiumsoftwarerebuild
comando pra jogar um último valor pro material

UPDATE materiais
SET
    "ultimoValorPago" = 3.80
WHERE id = 209;
