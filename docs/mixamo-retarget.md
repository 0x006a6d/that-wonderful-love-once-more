# Mixamo モーションを nikechan_player.vrm にリターゲットする手順

Windows 側の Godot エディタ (4.7.1) 上で行う作業です。Godot 未経験を前提に、順番どおりに進めれば動くように書いています。WSL では Vulkan が CPU 実行になり GUI が実用にならないため、この作業は必ず Windows 側の Godot で行ってください。

エディタの起動:
```
C:\Users\jun\godot\Godot_v4.7.1-stable_win64_console.exe
```
プロジェクトマネージャで `C:\That Wonderful Love, Once More` を開きます (project.godot がある場所)。

---

## 全体像

Mixamo のアニメーションは Mixamo 独自のボーン名 (mixamorig:Hips 等) を持ちます。nikechan_player.vrm のスケルトンは VRM/Humanoid のボーン構成です。両者を直接つなぐことはできないため、Godot の「Bone Map」機能で両方を共通規格 `SkeletonProfileHumanoid` にマッピングし、その共通規格を経由してモーションを流し込みます (リターゲット)。

作業は 3 つに分かれます。

1. Mixamo から攻撃モーションの FBX をダウンロードする
2. FBX を Godot に取り込み、Bone Map で SkeletonProfileHumanoid を割り当てる
3. nikechan_player.vrm のシーンにリターゲット済みアニメを流して再生確認する

---

## 1. Mixamo からモーションを入手する

1. https://www.mixamo.com にアクセスし、Adobe アカウントでログインします (無料)。
2. 上部の「Animations」タブを開き、検索欄に `Punching` など攻撃系のモーションを入力して 1 つ選びます。
3. 右側のダウンロードパネルで以下を設定します。
   - Format: **FBX for Unity (.fbx)**
   - Skin: **Without Skin** (メッシュ不要。モーションだけ欲しいため)
   - Frames per Second: 30 のままで可
   - Keyframe Reduction: none のままで可
4. 「DOWNLOAD」を押して FBX を保存します。

ファイル名は分かりやすく `punching.fbx` などにリネームしておくと後が楽です。

---

## 2. FBX を Godot に取り込み Bone Map を設定する

### 2-1. FBX を配置する

ダウンロードした FBX を、エクスプローラで次のフォルダに置きます (フォルダが無ければ作成):
```
C:\That Wonderful Love, Once More\assets\motions\
```
Godot 側 (res://) では `res://assets/motions/punching.fbx` として見えます。Godot エディタにフォーカスを戻すと自動でインポートが走ります。

### 2-2. FBX2glTF を要求されたら

Godot が「FBX のインポートには FBX2glTF が必要です」と表示することがあります。その場合はエディタが自動でダウンロードを提案するダイアログを出すので、それに従ってダウンロード・設定してください。一度設定すれば以降の FBX も自動で処理されます。
(手動指定が必要なら Editor → Editor Settings → FileSystem → Import → FBX2glTF Path で実行ファイルを指定します。)

### 2-3. Bone Map に SkeletonProfileHumanoid を割り当てる

1. 左下の「FileSystem」ドックで `res://assets/motions/punching.fbx` を選択します。
2. 上部に「Import」ドックが現れます (見当たらなければ FileSystem でファイルを選び直す)。
3. Import ドックのツリーで、モデル内の **Skeleton3D** ノードを選びます。
4. Skeleton3D の項目に **Retarget** セクションがあります。その中の **Bone Map** を開き、右側の値の欄から新規 **BoneMap** リソースを作成します。
5. 作成した BoneMap の中の **Profile** に **SkeletonProfileHumanoid** を指定します。
6. Godot が Mixamo のボーン名 (mixamorig:Hips 等) を humanoid 規格へ自動マッピングします。赤く残った未対応ボーンがあれば手動で対応ボーンをクリックして割り当てます (指ボーンなどが残ることがある。攻撃モーションの再生には主要ボーンが合っていれば足ります)。
7. Import ドック下部の **Reimport** を押して再インポートします。

これで FBX 側のアニメが humanoid 規格でリターゲット可能な状態になります。

---

## 3. nikechan_player.vrm にモーションを流して再生確認する

VRM 側も humanoid にマッピングされている必要があります。V-Sekai の VRM インポータは通常インポート時に Bone Map (SkeletonProfileHumanoid) を自動設定します。もし後述の再生でボーンがずれる場合は、`res://assets/vrm/nikechan_player.vrm` を選び 2-3 と同じ手順で Skeleton3D の Bone Map に SkeletonProfileHumanoid が設定されているか確認してください。

### 3-1. シーンに VRM を配置する

1. Scene → New Scene で新規 3D シーンを作り、ルートを Node3D にします。
2. FileSystem で `res://assets/vrm/nikechan_player.vrm` をシーンツリーへドラッグして子として配置します (インスタンス化)。
   - トゥーン (MToon) シェーダーとアウトラインで、平面的なアニメ調の見た目で立っていることを確認します。
3. シーンを `res://scenes/test_motion.tscn` などとして保存します。

### 3-2. リターゲット済みアニメを再生する

方式は 2 通り。まず簡単な方を試してください。

方式 A (最小・FBX 内蔵の AnimationPlayer を流用):
1. FileSystem で `punching.fbx` をシーンにドラッグして一時的に配置します。この FBX のインスタンス内に AnimationPlayer があり、リターゲット済みアニメが入っています。
2. その AnimationPlayer を選び、下部の Animation パネルで再生します。ボーンが humanoid 経由で解釈されるため、同じ humanoid プロファイルを持つスケルトンに適用できます。
   - 手早く見た目だけ確認するなら、FBX のスケルトンを直接再生して破綻しないことを見るだけでも一次確認になります。

方式 B (VRM 本体に載せる・実運用向け):
1. VRM インスタンス配下の AnimationPlayer (無ければ VRM ルートに AnimationPlayer を追加) を選びます。
2. Animation パネルの「Animation」→「Manage Animations / Load」から、FBX からインポートされたアニメーション (.res として書き出すか、FBX のシーンから取り出したアニメ) を読み込みます。
   - FBX を選択した状態の Import ドックで「Animation → Save to File / 個別アニメの書き出し」を有効にしておくと、`res://assets/motions/` にアニメ単体 (.res) が生成され、VRM の AnimationPlayer から読み込めます。
3. VRM の AnimationPlayer でそのアニメを再生します。両者とも SkeletonProfileHumanoid にマップされていれば、Mixamo モーションが nikechan のスケルトン上で再生されます。

### 3-3. 髪 (SpringBone) の揺れ確認

nikechan_player.vrm は VRM SpringBone を持ちます。VRM インポート時に VRMSecondary / spring bone のノードが構築されます。シーンを再生 (F6 で現在のシーンを実行、または Play) して、キャラが動いたときに髪が遅れて揺れる (追従して揺れる) ことを確認します。エディタのビューポートで止めているだけでは揺れないので、必ず実行して確認してください。

---

## 受け入れ条件 (確認観点)

以下 3 点がすべて満たされれば、この工程の受け入れ完了です。

- トゥーン表示で立つ: MToon シェーダー + アウトラインでアニメ調に表示され、nikechan が正しい姿勢で立っている。
- 髪 (SpringBone) が揺れる: シーン実行中にキャラが動くと髪が遅れて追従して揺れる。
- 借り物モーションが破綻なく再生される: Mixamo の攻撃モーションが、手足がねじれたり縮んだりせず、自然に再生される。

破綻する場合の典型原因は、FBX 側か VRM 側のどちらかで Bone Map (SkeletonProfileHumanoid) が未設定・不完全なことです。両方のスケルトンで humanoid プロファイルが割り当たっているかを最初に疑ってください。
